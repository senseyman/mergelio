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
