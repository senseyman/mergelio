import 'package:pub_semver/pub_semver.dart';

/// A release identity in the form pubspec writes it: a semantic version plus
/// the build number after '+'.
///
/// Semver deliberately ignores build metadata when ordering releases. This app
/// does not: two builds of the same version are a real sequence here, and a
/// hotfix that only moves the build number still has to win.
class AppVersion implements Comparable<AppVersion> {
  final Version semver;
  final int build;

  const AppVersion(this.semver, this.build);

  static AppVersion parse(String raw) {
    final text = raw.trim();
    final plus = text.indexOf('+');
    if (plus < 0) return AppVersion(Version.parse(text), 0);
    final build = int.tryParse(text.substring(plus + 1));
    if (build == null) {
      throw FormatException('Build number is not an integer', raw, plus + 1);
    }
    return AppVersion(Version.parse(text.substring(0, plus)), build);
  }

  static AppVersion? tryParse(String raw) {
    try {
      return parse(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  int compareTo(AppVersion other) {
    final byVersion = semver.compareTo(other.semver);
    return byVersion != 0 ? byVersion : build.compareTo(other.build);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && semver == other.semver && build == other.build;

  @override
  int get hashCode => Object.hash(semver, build);

  @override
  String toString() => build == 0 ? '$semver' : '$semver+$build';
}
