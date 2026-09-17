// Decoded GitHub JSON turned into the app's own models.
//
// Every read here is defensive. These parsers run against whatever the API
// actually sends, which is not always what its documentation describes, and a
// field that has changed shape must cost the user one missing row rather than
// a crashed client.

import '../../domain/forge/models.dart';

/// [value] when it is a JSON object, else null.
Map<String, Object?>? _obj(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// [value] when it is a non-empty string, else null.
String? _str(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is int ? value : null;

DateTime? _time(Object? value) {
  final raw = _str(value);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// The account a forge object belongs to. A deleted account arrives as null,
/// and that is not worth dropping the row over.
ForgeUser _user(Object? value) {
  final json = _obj(value);
  return ForgeUser(
    login: _str(json?['login']) ?? 'unknown',
    avatarUrl: _str(json?['avatar_url']) ?? '',
  );
}

PullRequestState _pullState(Map<String, Object?> json) {
  // merged_at outranks state: a landed request carries state "closed" too, and
  // collapsing it to closed would lose the distinction shown in the UI.
  if (_str(json['merged_at']) != null) return PullRequestState.merged;
  if (json['draft'] == true) return PullRequestState.draft;
  return _str(json['state']) == 'closed'
      ? PullRequestState.closed
      : PullRequestState.open;
}

/// Pull requests from a `/pulls` response.
///
/// Entries missing a number, a title or their branch refs are skipped: there
/// is nothing useful to show for one, and skipping costs a row where throwing
/// would cost the whole list.
List<PullRequest> parsePullRequests(Object? json) {
  if (json is! List) return const [];
  final out = <PullRequest>[];
  for (final entry in json) {
    final item = _obj(entry);
    if (item == null) continue;
    final number = _int(item['number']);
    final title = _str(item['title']);
    final head = _obj(item['head']);
    final base = _obj(item['base']);
    final sourceBranch = _str(head?['ref']);
    final targetBranch = _str(base?['ref']);
    final headSha = _str(head?['sha']);
    if (number == null ||
        title == null ||
        sourceBranch == null ||
        targetBranch == null ||
        headSha == null) {
      continue;
    }
    out.add(
      PullRequest(
        number: number,
        title: title,
        state: _pullState(item),
        author: _user(item['user']),
        sourceBranch: sourceBranch,
        targetBranch: targetBranch,
        headSha: headSha,
        updatedAt: _time(item['updated_at']),
      ),
    );
  }
  return List.unmodifiable(out);
}

/// A check run's state, which two fields carry between them.
///
/// While a run has not finished there is no conclusion yet and status decides;
/// once it completes, the conclusion does. An unrecognised value on either
/// lands on [CheckState.unknown], which the summary treats as not-green.
CheckState _checkRunState(Map<String, Object?> json) {
  switch (_str(json['status'])) {
    case 'queued':
    case 'waiting':
    case 'pending':
      return CheckState.queued;
    case 'in_progress':
      return CheckState.running;
    case 'completed':
      break;
    default:
      return CheckState.unknown;
  }
  switch (_str(json['conclusion'])) {
    case 'success':
      return CheckState.success;
    case 'failure':
    case 'timed_out':
    case 'action_required':
      return CheckState.failure;
    case 'cancelled':
      return CheckState.cancelled;
    case 'skipped':
    case 'neutral':
    case 'stale':
      return CheckState.skipped;
    default:
      return CheckState.unknown;
  }
}

/// A legacy commit status's state.
CheckState _commitStatusState(Object? value) {
  switch (_str(value)) {
    case 'success':
      return CheckState.success;
    case 'pending':
      return CheckState.running;
    case 'failure':
    case 'error':
      return CheckState.failure;
    default:
      return CheckState.unknown;
  }
}

/// The CI for one commit, from both APIs that carry it.
///
/// Older integrations post commit statuses; Actions and modern apps post check
/// runs. A repository may use either, both or neither, so both payloads are
/// optional and the two run lists are simply concatenated — the summary's own
/// precedence rules decide what they add up to.
ChecksSummary parseChecks({Object? combinedStatus, Object? checkRuns}) {
  final runs = <CheckRun>[];

  final statuses = _obj(combinedStatus)?['statuses'];
  if (statuses is List) {
    for (final entry in statuses) {
      final item = _obj(entry);
      final name = _str(item?['context']);
      if (item == null || name == null) continue;
      runs.add(
        CheckRun(
          name: name,
          state: _commitStatusState(item['state']),
          detailsHint: _str(item['description']) ?? '',
        ),
      );
    }
  }

  final checks = _obj(checkRuns)?['check_runs'];
  if (checks is List) {
    for (final entry in checks) {
      final item = _obj(entry);
      final name = _str(item?['name']);
      if (item == null || name == null) continue;
      runs.add(
        CheckRun(
          name: name,
          state: _checkRunState(item),
          detailsHint: _str(_obj(item['output'])?['title']) ?? '',
        ),
      );
    }
  }

  return ChecksSummary.from(List.unmodifiable(runs));
}

/// Label names from an issue's `labels` array, skipping anything that is not
/// a named object.
List<String> _labels(Object? value) {
  if (value is! List) return const [];
  final names = <String>[];
  for (final entry in value) {
    final name = _str(_obj(entry)?['name']);
    if (name != null) names.add(name);
  }
  return List.unmodifiable(names);
}

/// Issues from an `/issues` response.
///
/// Pull requests are filtered out. GitHub models every pull request as an
/// issue too, and returns them from this endpoint carrying an extra
/// `pull_request` key; left in, they would repeat the pull request list in
/// full inside the issue list.
List<Issue> parseIssues(Object? json) {
  if (json is! List) return const [];
  final out = <Issue>[];
  for (final entry in json) {
    final item = _obj(entry);
    if (item == null) continue;
    if (item.containsKey('pull_request')) continue;
    final number = _int(item['number']);
    final title = _str(item['title']);
    if (number == null || title == null) continue;
    out.add(
      Issue(
        number: number,
        title: title,
        state: _str(item['state']) == 'closed'
            ? IssueState.closed
            : IssueState.open,
        author: _user(item['user']),
        labels: _labels(item['labels']),
        updatedAt: _time(item['updated_at']),
      ),
    );
  }
  return List.unmodifiable(out);
}
