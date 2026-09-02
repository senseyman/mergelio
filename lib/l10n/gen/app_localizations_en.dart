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
  String get mergeResolve => 'Resolve';

  @override
  String a11yCommitRow(String sha, String author, String message) {
    return 'Commit $sha by $author: $message';
  }

  @override
  String get a11yWorkingChanges => 'Working tree changes';

  @override
  String get a11yCommitGraph => 'Commit history graph';

  @override
  String get shellAddRepository => 'Add repository';

  @override
  String get shellOpenRepoMenu => 'Open…';

  @override
  String get shellCloneRepoMenu => 'Clone…';

  @override
  String get shellCreateRepoMenu => 'Create…';

  @override
  String get shellRepoGroup => 'Repo group';

  @override
  String get shellAllGroups => 'All';

  @override
  String get shellNewGroup => 'New group';

  @override
  String get shellNewGroupMenu => 'New group…';

  @override
  String get shellGroupName => 'Group name';

  @override
  String get shellRenameGroup => 'Rename group';

  @override
  String get shellRenameMenu => 'Rename…';

  @override
  String get shellRenameGroupMenu => 'Rename group…';

  @override
  String get shellDeleteGroupTitle => 'Delete group?';

  @override
  String get shellDeleteGroupMenu => 'Delete group…';

  @override
  String shellDeleteGroupBody(String name) {
    return '\"$name\" is removed from the switcher. Repositories in it stay open, without a group.';
  }

  @override
  String get shellCloseTab => 'Close tab';

  @override
  String get shellCloseOthers => 'Close others';

  @override
  String shellRemoveFromGroup(String name) {
    return 'Remove from $name';
  }

  @override
  String shellMoveToGroup(String name) {
    return 'Move to $name';
  }

  @override
  String get tabWorktree => 'Worktree';

  @override
  String tabWorktreeOf(String parent) {
    return 'Worktree of $parent';
  }

  @override
  String get wtAdd => 'Add worktree';

  @override
  String get wtLocation => 'Location';

  @override
  String get wtBrowse => 'Browse…';

  @override
  String get wtNewBranch => 'New branch';

  @override
  String get wtFrom => 'from';

  @override
  String get wtExistingBranch => 'Existing branch';

  @override
  String get wtDetachedAt => 'Detached at';

  @override
  String wtHeldBy(String name) {
    return '— in $name';
  }

  @override
  String get wtBranchExists => 'That branch already exists';

  @override
  String get wtDirNotEmpty => 'That directory is not empty';

  @override
  String get wtSubmodulesNote =>
      'Submodules are not checked out in a new worktree; initialise them there yourself.';

  @override
  String get wtOpenInNewTab => 'Open in a new tab';

  @override
  String get wtRemoveTitle => 'Remove worktree?';

  @override
  String wtCheckedOutBranch(String branch) {
    return 'Checked out: $branch';
  }

  @override
  String get wtDirDeleted => 'The directory will be deleted.';

  @override
  String get wtRemove => 'Remove';

  @override
  String get wtHasChangesTitle => 'Worktree has changes';

  @override
  String get wtForcingDiscards => 'Forcing discards those changes.';

  @override
  String get wtForceRemove => 'Force remove';

  @override
  String get wtMoveTitle => 'Move worktree';

  @override
  String get wtAlreadyThere => 'That is where it already is';

  @override
  String wtNewLocationFor(String name) {
    return 'New location for $name';
  }

  @override
  String get wtMove => 'Move';

  @override
  String get wtAlreadyCheckedOut => 'Already checked out';

  @override
  String wtCheckedOutInWorktreeAt(String branch) {
    return '$branch is checked out in the worktree at';
  }

  @override
  String get wtTwoPlacesWarning =>
      'Checking out anyway puts the branch in two places at once; commits made in one leave the other behind.';

  @override
  String get wtCheckoutAnyway => 'Checkout anyway';

  @override
  String get wtOpenWorktree => 'Open worktree';

  @override
  String get wtPruneTitle => 'Prune stale worktrees';

  @override
  String get wtNothingToPrune => 'Nothing to prune.';

  @override
  String get wtEntriesWillBeRemoved => 'These entries will be removed:';

  @override
  String get wtPrune => 'Prune';

  @override
  String get sbRepository => 'Repository';

  @override
  String get sbCollapse => 'Collapse';

  @override
  String get sbCouldNotRead => 'Could not read repository';

  @override
  String get sbRetry => 'Retry';

  @override
  String get sbBranches => 'Branches';

  @override
  String get sbNoBranches => 'No branches';

  @override
  String get sbRemotes => 'Remotes';

  @override
  String get sbNoRemotes => 'No remotes';

  @override
  String get sbTags => 'Tags';

  @override
  String get sbNoTags => 'No tags';

  @override
  String get sbStashes => 'Stashes';

  @override
  String get sbNoStashes => 'No stashes';

  @override
  String get sbSubmodules => 'Submodules';

  @override
  String get sbNoSubmodules => 'No submodules';

  @override
  String get sbAddRemoteRow => 'Add remote…';

  @override
  String get sbAddRemoteTitle => 'Add remote';

  @override
  String get sbAdd => 'Add';

  @override
  String get sbAddSubmoduleRow => 'Add submodule…';

  @override
  String get sbPop => 'Pop';

  @override
  String get sbInit => 'Init';

  @override
  String get sbUpdate => 'Update';

  @override
  String get sbUpdateToRemote => 'Update to remote';

  @override
  String get sbSync => 'Sync';

  @override
  String get sbDeinit => 'Deinit';

  @override
  String get sbReset => 'Reset';

  @override
  String sbResetToUpstreamTitle(String branch, String upstream) {
    return 'Reset $branch to $upstream?';
  }

  @override
  String sbResetUnpushedBody(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count unpushed commits on $branch will be removed. This can be undone.',
      one:
          '$count unpushed commit on $branch will be removed. This can be undone.',
    );
    return '$_temp0';
  }

  @override
  String sbResetMovedBody(String branch, String upstream) {
    return '$branch will be moved to $upstream. This can be undone.';
  }

  @override
  String get sbCheckout => 'Checkout';

  @override
  String get sbMergeIntoCurrent => 'Merge into current';

  @override
  String get sbRebaseOntoCurrent => 'Rebase onto current';

  @override
  String get sbSetUpstreamItem => 'Set upstream…';

  @override
  String sbSetUpstreamTitle(String branch) {
    return 'Set upstream for $branch';
  }

  @override
  String sbSetUpstreamHint(String branch) {
    return 'e.g. origin/$branch';
  }

  @override
  String get sbResetToRemote => 'Reset to remote…';

  @override
  String get sbRenameItem => 'Rename…';

  @override
  String get sbRenameBranchTitle => 'Rename branch';

  @override
  String get sbDeleteBranch => 'Delete branch';

  @override
  String sbDeleteBranchTitle(String branch) {
    return 'Delete $branch?';
  }

  @override
  String get sbDeleteBranchBody =>
      'The branch ref will be removed. This can be undone.';

  @override
  String get sbDeleteBranchAndRemote => 'Delete branch and remote…';

  @override
  String sbDeleteBothTitle(String branch, String upstream) {
    return 'Delete $branch and $upstream?';
  }

  @override
  String get sbDeleteBothBody =>
      'The branch will be removed here and on the remote. Only the local half can be undone.';

  @override
  String get sbDeleteBoth => 'Delete both';

  @override
  String sbCheckedOutIn(String name) {
    return 'Checked out in $name';
  }

  @override
  String sbMergeSourceInto(String source, String target) {
    return 'Merge «$source» into «$target»';
  }

  @override
  String sbRebaseSourceOnto(String source, String target) {
    return 'Rebase «$source» onto «$target»';
  }

  @override
  String sbTipSwitchHint(String branch) {
    return 'Click to show its tip · double-click to switch to $branch';
  }

  @override
  String sbTipCheckoutHint(String name) {
    return 'Click to show its tip · double-click to check out $name';
  }

  @override
  String get sbHasLocalBranch => 'Has a local branch';

  @override
  String sbSwitchTo(String branch) {
    return 'Switch to $branch';
  }

  @override
  String sbCheckOutNamed(String name) {
    return 'Check out $name';
  }

  @override
  String sbMergeNamedIntoCurrent(String name) {
    return 'Merge $name into current';
  }

  @override
  String sbResetToThis(String branch) {
    return 'Reset $branch to this';
  }

  @override
  String sbDeleteRemoteBranchTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String sbDeleteRemoteBranchBody(String remote) {
    return 'The branch will be deleted on $remote. Any local branch of the same name stays. This cannot be undone.';
  }

  @override
  String sbDeleteNamedItem(String name) {
    return 'Delete $name…';
  }

  @override
  String sbFetchRemote(String remote) {
    return 'Fetch $remote';
  }

  @override
  String get sbPrune => 'Prune';

  @override
  String get sbCopyUrl => 'Copy URL';

  @override
  String get sbEditRemoteTitle => 'Edit remote';

  @override
  String get sbEditRemoteItem => 'Edit remote…';

  @override
  String sbRemoveRemoteTitle(String remote) {
    return 'Remove remote $remote?';
  }

  @override
  String get sbRemoveRemoteBody =>
      'Its remote-tracking branches go with it. Undo restores the remote; fetch to bring the branches back.';

  @override
  String get sbRemove => 'Remove';

  @override
  String get sbRemoveRemoteItem => 'Remove remote…';

  @override
  String get sbPushTag => 'Push tag';

  @override
  String get sbCopyName => 'Copy name';

  @override
  String sbDeleteTagTitle(String tag) {
    return 'Delete tag $tag?';
  }

  @override
  String get sbDeleteTagBody =>
      'The tag will be removed locally. This can be undone.';

  @override
  String get sbDeleteTag => 'Delete tag';

  @override
  String sbDropStashTitle(String ref) {
    return 'Drop $ref?';
  }

  @override
  String get sbDropStashBody =>
      'The stash will be deleted. An Undo toast lets you restore it.';

  @override
  String get sbDrop => 'Drop';

  @override
  String sbRemoveSubmoduleTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String sbRemoveSubmoduleBody(String path) {
    return 'The submodule at $path will be deinitialized and removed from .gitmodules. This cannot be undone.';
  }

  @override
  String get discard => 'Discard';

  @override
  String get create => 'Create';

  @override
  String get edit => 'Edit';

  @override
  String get rename => 'Rename';

  @override
  String get commonUnsavedChanges => 'Unsaved changes';

  @override
  String get commonFileChangedOnDisk => 'File changed on disk';

  @override
  String get commonOverwrite => 'Overwrite';

  @override
  String get diffDiscardEditsTitle => 'Discard edits?';

  @override
  String diffDiscardEditsBody(String path) {
    return 'What you typed here has not been written to $path.';
  }

  @override
  String get diffSelectAll => 'Select all';

  @override
  String diffDiscardFileTitle(String path) {
    return 'Discard $path?';
  }

  @override
  String get diffDiscardFileBody =>
      'This deletes the untracked file. You can undo it.';

  @override
  String get filesEditor => 'Editor';

  @override
  String filesClosePath(String path) {
    return 'Close $path';
  }

  @override
  String get filesName => 'Name';

  @override
  String get filesRenameTitle => 'Rename';

  @override
  String get filesNewName => 'New name';

  @override
  String filesDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String filesDiscardChangesTitle(String name) {
    return 'Discard changes to $name?';
  }

  @override
  String get filesRefresh => 'Refresh';

  @override
  String get filesCollapse => 'Collapse';

  @override
  String wtpAlsoDeleteUntracked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Also delete $count untracked files',
      one: 'Also delete $count untracked file',
    );
    return '$_temp0';
  }

  @override
  String get diffDiscardHunkTitle => 'Discard hunk?';

  @override
  String diffDiscardLinesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Discard $count lines?',
      one: 'Discard $count line?',
    );
    return '$_temp0';
  }

  @override
  String get diffDiscardLinesBody =>
      'This removes the selected changes from the working tree. You can undo it.';
}
