// Decoded GitLab JSON turned into the app's own models.
//
// Every read here is defensive in the same way the GitHub parser is:
// parsers run against what the API actually sends, not always what the
// documentation describes, so a field that changed shape costs the user
// one missing row, never a crashed client.

import '../../domain/forge/models.dart';

/// [value] as a JSON object, else null.
Map<String, Object?>? _obj(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// [value] as a non-empty string, else null.
String? _str(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is int ? value : null;

DateTime? _time(Object? value) {
  final raw = _str(value);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// The account a forge object belongs to. A deleted account arrives as
/// null, which is not worth dropping the row over.
ForgeUser _user(Object? value) {
  final json = _obj(value);
  return ForgeUser(
    login: _str(json?['username']) ?? 'unknown',
    displayName: _str(json?['name']) ?? '',
    avatarUrl: _str(json?['avatar_url']) ?? '',
  );
}

/// A merge request's state, GitLab's `state`, `draft` and legacy
/// `work_in_progress` fields carry between them.
///
/// `draft` outranks `state`: a draft the author has not marked ready must
/// never be collapsed into plain open, and older GitLab releases only ever
/// sent `work_in_progress`, so that spelling is read the same way.
PullRequestState _mergeRequestState(Map<String, Object?> json) {
  if (json['draft'] == true || json['work_in_progress'] == true) {
    return PullRequestState.draft;
  }
  return switch (_str(json['state'])) {
    'merged' => PullRequestState.merged,
    'closed' => PullRequestState.closed,
    // 'locked' means the discussion is frozen, not that the request left
    // open, so it belongs with open rather than closed.
    _ => PullRequestState.open,
  };
}

/// Merge requests from a `/merge_requests` response.
///
/// Entries missing a number, title, either branch, or a head sha are
/// skipped: there is no row worth drawing without them, and no safe value
/// to invent for a commit reference.
List<PullRequest> parseMergeRequests(Object? json) {
  if (json is! List) return const [];
  final out = <PullRequest>[];
  for (final entry in json) {
    final item = _obj(entry);
    if (item == null) continue;
    // `iid` is the number a person sees and a URL uses. The global `id`
    // addresses an entirely different merge request in a different
    // project and must never surface here.
    final number = _int(item['iid']);
    final title = _str(item['title']);
    final sourceBranch = _str(item['source_branch']);
    final targetBranch = _str(item['target_branch']);
    final headSha = _str(item['sha']);
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
        state: _mergeRequestState(item),
        author: _user(item['author']),
        sourceBranch: sourceBranch,
        targetBranch: targetBranch,
        headSha: headSha,
        updatedAt: _time(item['updated_at']),
      ),
    );
  }
  return List.unmodifiable(out);
}

/// One job's state, or null when the job carries no outcome to report. An
/// unrecognised value lands on [CheckState.unknown] so a status version this
/// client has never seen is never reported passing.
CheckState? _statusState(Map<String, Object?> json) {
  // A job GitLab allowed to fail does not fail the pipeline, so reporting
  // failure here would claim a verdict GitLab itself never reached.
  // Unknown leaves it mixed, claiming nothing either way.
  if (json['allow_failure'] == true && _str(json['status']) == 'failed') {
    return CheckState.unknown;
  }
  return switch (_str(json['status'])) {
    'created' || 'pending' => CheckState.queued,
    'running' => CheckState.running,
    'success' => CheckState.success,
    'failed' => CheckState.failure,
    'canceled' => CheckState.cancelled,
    // Skipped is an outcome GitLab actually reached: the job was considered
    // and deliberately not run.
    'skipped' => CheckState.skipped,
    // A manual job waiting for someone to press it is not an outcome at
    // all, and GitLab does not hold the pipeline's own verdict back for
    // one. Carrying it as any state would leave a fully green,
    // manually-gated pipeline reading as something other than green here,
    // disagreeing with what GitLab itself shows.
    'manual' => null,
    _ => CheckState.unknown,
  };
}

/// CI for one commit, from a `/repository/commits/<ref>/statuses`
/// response.
///
/// The endpoint returns every attempt at a job, so a retried job appears
/// more than once under one name. Only the newest attempt counts: ids
/// increase, and letting an old failure stand alongside the green retry
/// that replaced it would report the commit red forever, since
/// ChecksSummary ranks failure highest.
///
/// A job with no outcome of its own is still tracked by name here and
/// dropped at the end, rather than skipped on the way in, so that the newest
/// attempt keeps deciding: an older attempt it replaced must not stand in
/// for a result that no longer exists.
ChecksSummary parseCommitStatuses(Object? json) {
  if (json is! List) return const ChecksSummary(overall: ChecksOverall.none);
  final newest = <String, ({int id, CheckRun? run})>{};
  for (final entry in json) {
    final item = _obj(entry);
    final name = _str(item?['name']);
    if (item == null || name == null) continue;
    final id = _int(item['id']) ?? 0;
    final existing = newest[name];
    if (existing != null && existing.id >= id) continue;
    final state = _statusState(item);
    newest[name] = (
      id: id,
      run: state == null
          ? null
          : CheckRun(
              name: name,
              state: state,
              detailsHint: _str(item['description']) ?? '',
            ),
    );
  }
  return ChecksSummary.from(
    List.unmodifiable([for (final entry in newest.values) ?entry.run]),
  );
}

/// Labels, since GitLab sends them as plain strings.
List<String> _labels(Object? value) {
  if (value is! List) return const [];
  final names = <String>[];
  for (final entry in value) {
    final name = _str(entry);
    if (name != null) names.add(name);
  }
  return List.unmodifiable(names);
}

/// Issues from an `/issues` response.
///
/// Unlike GitHub, merge requests live on their own endpoint, so nothing
/// needs to be filtered back out here.
List<Issue> parseGitlabIssues(Object? json) {
  if (json is! List) return const [];
  final out = <Issue>[];
  for (final entry in json) {
    final item = _obj(entry);
    if (item == null) continue;
    final number = _int(item['iid']);
    final title = _str(item['title']);
    if (number == null || title == null) continue;
    out.add(
      Issue(
        number: number,
        title: title,
        state: _str(item['state']) == 'closed'
            ? IssueState.closed
            : IssueState.open,
        author: _user(item['author']),
        labels: _labels(item['labels']),
        updatedAt: _time(item['updated_at']),
      ),
    );
  }
  return List.unmodifiable(out);
}
