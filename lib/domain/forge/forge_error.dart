// Why a forge call did not produce data. Each variant exists because it needs
// a different answer from the user: reconnect, wait, check scopes, or retry.

/// A forge request that produced no usable data.
sealed class ForgeError implements Exception {
  const ForgeError();
}

/// The token was rejected. It expired, was revoked, or was never valid.
class ForgeUnauthenticated extends ForgeError {
  const ForgeUnauthenticated();
  @override
  String toString() => 'ForgeUnauthenticated';
}

/// The forge is refusing further requests until [resetAt], which some hosts
/// decline to tell us.
class ForgeRateLimited extends ForgeError {
  final DateTime? resetAt;
  const ForgeRateLimited(this.resetAt);
  @override
  String toString() => 'ForgeRateLimited(resetAt: $resetAt)';
}

/// The resource does not exist, or exists and this token cannot see it. The
/// forge deliberately does not distinguish the two for private resources, so
/// neither does this.
class ForgeNotVisible extends ForgeError {
  const ForgeNotVisible();
  @override
  String toString() => 'ForgeNotVisible';
}

/// The request never reached the forge.
class ForgeOffline extends ForgeError {
  final String detail;
  const ForgeOffline(this.detail);
  @override
  String toString() => 'ForgeOffline($detail)';
}

/// The forge answered, badly.
class ForgeServerFault extends ForgeError {
  final int status;
  const ForgeServerFault(this.status);
  @override
  String toString() => 'ForgeServerFault($status)';
}

/// The forge answered with something this version cannot read.
class ForgeMalformed extends ForgeError {
  final String detail;
  const ForgeMalformed(this.detail);
  @override
  String toString() => 'ForgeMalformed($detail)';
}

/// Header carrying the epoch second a rate limit lifts. GitHub and GitLab
/// spell it differently and a response may carry either.
const _resetHeaders = ['x-ratelimit-reset', 'ratelimit-reset'];

DateTime? _resetAt(Map<String, String> headers) {
  for (final name in _resetHeaders) {
    final raw = headers[name];
    if (raw == null) continue;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null) continue;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
  return null;
}

bool _limitExhausted(Map<String, String> headers) {
  for (final name in ['x-ratelimit-remaining', 'ratelimit-remaining']) {
    if (int.tryParse(headers[name]?.trim() ?? '') == 0) return true;
  }
  return false;
}

/// The failure a non-success [status] represents. [headers] must be keyed in
/// lower case, as an HTTP response's headers already are.
///
/// Only call this for a status that is not a success: there is no variant for
/// one, and inventing a failure for a 200 would hide real data.
ForgeError forgeErrorForStatus(int status, Map<String, String> headers) {
  if (status == 401) return const ForgeUnauthenticated();
  if (status == 429) return ForgeRateLimited(_resetAt(headers));
  if (status == 403) {
    // A 403 means either "you have spent your quota" or "your token is not
    // allowed here". Only the headers tell them apart, and sending someone to
    // wait out a limit they have not hit wastes their time.
    if (_limitExhausted(headers) || _resetAt(headers) != null) {
      return ForgeRateLimited(_resetAt(headers));
    }
    return const ForgeNotVisible();
  }
  if (status == 404) return const ForgeNotVisible();
  return ForgeServerFault(status);
}
