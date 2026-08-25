// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Mergelio';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get apply => 'Apply';

  @override
  String get import => 'Import';

  @override
  String get export => 'Export';

  @override
  String get tooltipTerminal => 'Terminal (⌘`)';

  @override
  String get tooltipSearch => 'Search (⌘F)';

  @override
  String get tooltipPalette => 'Command palette (⌘K)';

  @override
  String get tooltipPreferences => 'Preferences (⌘,)';

  @override
  String get tooltipProfiles => 'Profiles';

  @override
  String get tooltipProjectFiles => 'Project files';

  @override
  String get tooltipHistory => 'History';

  @override
  String get opFetch => 'Fetch';

  @override
  String get opPull => 'Pull';

  @override
  String get opPullRebase => 'Pull (rebase)';

  @override
  String get opPush => 'Push';

  @override
  String get opPushOrigin => 'Push origin';

  @override
  String get opForcePush => 'Force-push (with lease)';

  @override
  String get opUndo => 'Undo';

  @override
  String get opRedo => 'Redo';

  @override
  String get welcomeOpen => 'Open';

  @override
  String get welcomeClone => 'Clone';

  @override
  String get welcomeCreate => 'Create';

  @override
  String get welcomeRecents => 'Recent repositories';

  @override
  String get welcomeNoRecents => 'No recent repositories yet';

  @override
  String get prefsTitle => 'Preferences';

  @override
  String get prefsTabGeneral => 'General';

  @override
  String get prefsTabAppearance => 'Appearance';

  @override
  String get prefsTabShortcuts => 'Shortcuts';

  @override
  String get prefsTabCredentials => 'Credentials';

  @override
  String get prefsAutoFetch => 'Auto-fetch';

  @override
  String get prefsAutoFetchInterval => 'Auto-fetch interval';

  @override
  String get prefsConfirmDestructive => 'Confirm destructive actions';

  @override
  String get prefsRestoreTabs => 'Restore tabs on launch';

  @override
  String get prefsTelemetry => 'Share anonymous usage data';

  @override
  String get prefsZoom => 'Zoom';

  @override
  String get prefsGroupStyle => 'Group switcher';

  @override
  String get prefsPullStrategy => 'Pull strategy';

  @override
  String get prefsDateFormat => 'Date format';

  @override
  String get prefsGraphColumns => 'Graph columns';

  @override
  String get prefsCompactRows => 'Compact rows';

  @override
  String get prefsLanguage => 'Language';

  @override
  String get prefsTheme => 'Theme';

  @override
  String get prefsAccent => 'Accent';

  @override
  String get prefsBranchColours => 'Branch colours';

  @override
  String get prefsResetColours => 'Reset colours';

  @override
  String get prefsSavedThemes => 'Saved themes';

  @override
  String get prefsSaveCurrent => 'Save current…';

  @override
  String get strategyMerge => 'merge';

  @override
  String get strategyRebase => 'rebase';

  @override
  String get dateMedium => 'medium';

  @override
  String get dateIso => 'ISO';

  @override
  String get dateShort => 'short';

  @override
  String get prefsClockFormat => 'Clock';

  @override
  String get clock24 => '24-hour';

  @override
  String get clock12 => '12-hour';

  @override
  String get themeDark => 'dark';

  @override
  String get themeLight => 'light';

  @override
  String get themeSystem => 'system';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get graphHistory => 'HISTORY';

  @override
  String get graphCompact => 'Compact';

  @override
  String get filterHideMerges => 'Hide merges';

  @override
  String get filterHideTags => 'Hide tags';

  @override
  String get filterContentRegex => 'Regex';

  @override
  String get searchContentHint => 'In diffs…';

  @override
  String get searchContentHelp => 'Commits that added or removed this text';

  @override
  String get searchContentRegexHelp =>
      'Commits with an added or removed line matching this regular expression';

  @override
  String get searchRunning => 'Searching…';

  @override
  String get searchNoMatches => 'No matches';

  @override
  String get menuCheckout => 'Checkout this commit';

  @override
  String get menuCreateBranch => 'Create branch here';

  @override
  String get menuCreateTag => 'Create tag here';

  @override
  String get menuCherryPick => 'Cherry-pick';

  @override
  String get menuRevert => 'Revert';

  @override
  String get menuRebaseHere => 'Rebase to here…';

  @override
  String get menuResetHard => 'Reset here (--hard)';

  @override
  String get menuEditMessage => 'Edit message…';

  @override
  String get menuCopySummary => 'Copy summary';

  @override
  String get menuCopyDescription => 'Copy description';

  @override
  String get menuCopyMessage => 'Copy message';

  @override
  String get menuCopySha => 'Copy SHA';

  @override
  String get rewordTitle => 'Edit commit message';

  @override
  String get rewordPushedTitle => 'Rewrite a pushed commit?';

  @override
  String rewordPushedBody(String branches) {
    return 'This commit is already on $branches. Changing its message rewrites history, so the branch will need a force push and anyone who pulled it will have to reset.';
  }

  @override
  String get rewordPushedConfirm => 'Rewrite anyway';

  @override
  String get mergeResolveConflicts => 'Resolve conflicts';

  @override
  String get mergeRebase => 'Rebase';

  @override
  String mergeCherryPick(String sha) {
    return 'Cherry-pick $sha';
  }

  @override
  String mergeRevert(String sha) {
    return 'Revert $sha';
  }

  @override
  String mergeInto(String branch, String into) {
    return 'Merge $branch → $into';
  }

  @override
  String mergeBranch(String branch) {
    return 'Merge $branch';
  }

  @override
  String mergeResolvedCount(int resolved, int total) {
    return '$resolved / $total resolved';
  }

  @override
  String get mergeNextUnresolved => 'Next unresolved';

  @override
  String get mergeAbort => 'Abort';

  @override
  String get mergeFinish => 'Finish';

  @override
  String get mergeFinishRebase => 'Finish rebase';

  @override
  String get mergeFinishCherryPick => 'Finish cherry-pick';

  @override
  String get mergeFinishRevert => 'Finish revert';

  @override
  String get mergeFinishMerge => 'Finish merge';

  @override
  String a11yCommitRow(String sha, String author, String message) {
    return 'Commit $sha by $author: $message';
  }

  @override
  String get a11yWorkingChanges => 'Working tree changes';

  @override
  String get a11yCommitGraph => 'Commit history graph';
}
