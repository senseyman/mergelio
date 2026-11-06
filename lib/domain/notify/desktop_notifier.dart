import '../forge/forge_host.dart';

/// Where a notification leads when the user clicks it: a repo, optionally a
/// specific pull request on its forge.
class NotificationTarget {
  const NotificationTarget({
    required this.repoPath,
    this.kind,
    this.prNumber,
    this.targetBranch,
  });

  final String repoPath;
  final ForgeKind? kind;
  final int? prNumber;
  final String? targetBranch;

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.repoPath == repoPath &&
      other.kind == kind &&
      other.prNumber == prNumber &&
      other.targetBranch == targetBranch;

  @override
  int get hashCode => Object.hash(repoPath, kind, prNumber, targetBranch);
}

class AppNotification {
  const AppNotification({
    required this.title,
    required this.body,
    required this.target,
  });

  final String title;
  final String body;
  final NotificationTarget target;
}

/// Shows operating-system notifications and reports which one was clicked.
abstract class DesktopNotifier {
  Future<void> show(AppNotification n);
  Stream<NotificationTarget> get clicks;
  void dispose();
}

/// Used when the platform cannot show notifications: every call is a no-op.
class NullDesktopNotifier implements DesktopNotifier {
  @override
  Future<void> show(AppNotification n) async {}

  @override
  Stream<NotificationTarget> get clicks => const Stream.empty();

  @override
  void dispose() {}
}
