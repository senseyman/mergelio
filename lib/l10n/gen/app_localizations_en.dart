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
  String get opPushOptions => 'Push…';

  @override
  String get welcomeOpen => 'Open';

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
  String get prefsPullAutostash => 'Autostash on pull';

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
  String get graphLoadingOlder => 'Loading older commits…';

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
  String get menuCreateFixup => 'Prepare fixup for this commit';

  @override
  String get menuResetMixed => 'Reset here (--mixed)';

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
  String get menuMarkCompare => 'Mark for comparison';

  @override
  String get menuClearCompareMark => 'Clear comparison mark';

  @override
  String menuCompareWith(String ref) {
    return 'Compare with $ref';
  }

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
  String get sbReflog => 'Reflog';

  @override
  String get sbNoReflog => 'No reflog entries';

  @override
  String get sbCopySha => 'Copy SHA';

  @override
  String get sbReflogFailed => 'Could not read the reflog';

  @override
  String sbReflogTruncated(int count) {
    return 'Showing the first $count entries';
  }

  @override
  String sbReflogDetachTitle(String sha) {
    return 'Check out $sha?';
  }

  @override
  String get sbReflogDetachBody =>
      'Leaves HEAD detached at this commit. No branch moves, so you can return to the branch you were on at any time.';

  @override
  String get sbReflogDetach => 'Check out';

  @override
  String get sbReflogFilter => 'Filter entries';

  @override
  String get sbReflogNoMatches => 'No matching entries';

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
  String get sbCompareWithCurrent => 'Compare with current';

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
  String bdFastForward(String source, String target) {
    return 'Fast-forward «$target» to «$source»';
  }

  @override
  String bdMoveHere(String source, String target) {
    return 'Move «$source» to «$target»';
  }

  @override
  String bdResetSoft(String source, String target) {
    return 'Reset «$source» to «$target» (--soft)';
  }

  @override
  String bdResetMixed(String source, String target) {
    return 'Reset «$source» to «$target» (--mixed)';
  }

  @override
  String bdResetHard(String source, String target) {
    return 'Reset «$source» to «$target» (--hard)';
  }

  @override
  String bdCherryPick(String source, String target) {
    return 'Cherry-pick «$target» onto «$source»';
  }

  @override
  String bdMergeBody(String source, String target) {
    return 'Switches to «$target» and merges «$source» into it.';
  }

  @override
  String bdRebaseBody(String source, String target) {
    return 'Switches to «$source» and replays its commits onto «$target».';
  }

  @override
  String bdFastForwardBody(String source, String target) {
    return 'Moves «$target» forward to «$source». No new commit is made.';
  }

  @override
  String bdMoveHereBody(String source, String target) {
    return 'Points «$source» at «$target» without switching to it. Commits only «$source» had may become unreachable; undo puts it back.';
  }

  @override
  String bdResetSoftBody(String source, String target) {
    return 'Moves «$source» to «$target». Changes from the commits it leaves behind stay staged.';
  }

  @override
  String bdResetMixedBody(String source, String target) {
    return 'Moves «$source» to «$target». Changes from the commits it leaves behind stay in the working tree, unstaged.';
  }

  @override
  String bdResetHardBody(String source, String target) {
    return 'Moves «$source» to «$target» and discards the commits it leaves behind. Uncommitted work is stashed first.';
  }

  @override
  String bdCherryPickBody(String source, String target) {
    return 'Switches to «$source» and applies commit «$target» on top of it.';
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
  String get sbDeleteRemoteTag => 'Delete tag on remote…';

  @override
  String sbDeleteRemoteTagTitle(String tag, String remote) {
    return 'Delete tag $tag on $remote?';
  }

  @override
  String get sbDeleteRemoteTagBody =>
      'The tag is removed from the remote. The local tag is kept, and this cannot be undone.';

  @override
  String get sbCopyName => 'Copy name';

  @override
  String sbCopyNamed(String name) {
    return 'Copy «$name»';
  }

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

  @override
  String get bbOpenRepoFirst => 'Open a repository first';

  @override
  String get bbOperationRunning => 'An operation is already running';

  @override
  String get bbNoRemote => 'No remote configured';

  @override
  String bbUndoLabelled(String label) {
    return 'Undo $label (⌘Z)';
  }

  @override
  String get bbUndo => 'Undo (⌘Z)';

  @override
  String bbRedoLabelled(String label) {
    return 'Redo $label (⌘⇧Z)';
  }

  @override
  String get bbRedo => 'Redo (⌘⇧Z)';

  @override
  String get bbFetchOrigin => 'Fetch origin';

  @override
  String get bbFetchAllRemotes => 'Fetch all remotes';

  @override
  String get bbPullAllRemotes => 'Pull (all remotes)';

  @override
  String get bbPullFfOnly => 'Pull (fast-forward only)';

  @override
  String get bbPullMerge => 'Pull (merge)';

  @override
  String get bbForcePushTitle => 'Force-push?';

  @override
  String get bbForcePushBody =>
      'This overwrites the remote branch with your local history (using --force-with-lease, which still refuses if the remote moved unexpectedly).';

  @override
  String get bbForcePush => 'Force-push';

  @override
  String get bbBranch => 'Branch';

  @override
  String get bbMerge => 'Merge';

  @override
  String get bbStash => 'Stash';

  @override
  String get sbarNoProfile => 'No profile';

  @override
  String get sbarNoRepository => 'No repository';

  @override
  String get sbarDark => 'Dark';

  @override
  String get sbarLight => 'Light';

  @override
  String sbarCancelBusy(String label) {
    return 'Cancel $label';
  }

  @override
  String get tbComingLater => 'Coming in a later stage';

  @override
  String get tbTerminal => 'Terminal';

  @override
  String get tbGlobalSearch => 'Global search';

  @override
  String get tbCommandPalette => 'Command palette';

  @override
  String get railExpand => 'Expand';

  @override
  String gaCheckoutBranch(String name) {
    return 'Checkout: $name';
  }

  @override
  String gaFlyToCommit(String sha, String message) {
    return 'Fly to: $sha  $message';
  }

  @override
  String get rmcMomentsAgo => 'moments ago';

  @override
  String rmcMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String rmcHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String rmcDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get rmcNotFetched => 'This repository has not fetched yet.';

  @override
  String rmcLastFetched(String age) {
    return 'Last fetched $age.';
  }

  @override
  String rmcMergeFrom(String remote) {
    return 'Merge from $remote?';
  }

  @override
  String rmcStaleWarning(String source, String remote) {
    return '$source is a remote-tracking branch. It is only as current as the last fetch from $remote.';
  }

  @override
  String get rmcMergeAsIs => 'Merge as-is';

  @override
  String get rmcFetchAndMerge => 'Fetch and merge';

  @override
  String get ropCreateBranchTitle => 'Create branch';

  @override
  String get ropCurrentBranch => 'current branch';

  @override
  String ropMergeIntoTitle(String branch) {
    return 'Merge into $branch';
  }

  @override
  String get ropCreateTagTitle => 'Create tag';

  @override
  String get ropTagName => 'Tag name';

  @override
  String get ropType => 'Type';

  @override
  String get ropTagMessage => 'Tag message';

  @override
  String get ropPushTitle => 'Push';

  @override
  String get ropPushRemote => 'Remote';

  @override
  String get ropPushTags => 'Also push all tags';

  @override
  String get ropPushForce => 'Force (with lease)';

  @override
  String get ropPushNoRemotes =>
      'This repository has no remotes. Add one before pushing.';

  @override
  String get ropStashChangesTitle => 'Stash changes';

  @override
  String get ropBranchName => 'Branch name';

  @override
  String get ropStartFrom => 'Start from';

  @override
  String get ropCheckoutAfterCreating => 'Check out after creating';

  @override
  String get ropNoOtherBranches => 'No other branches to merge.';

  @override
  String get ropBranchToMerge => 'Branch to merge';

  @override
  String get ropMerge => 'Merge';

  @override
  String get ropSquash => 'Squash (stage, do not commit)';

  @override
  String get ropNoCommit => 'Stage the merge, do not commit';

  @override
  String get ropFavorLabel => 'If both sides changed the same lines';

  @override
  String get ropFavorAsk => 'Ask';

  @override
  String get ropFavorOurs => 'Ours';

  @override
  String get ropFavorTheirs => 'Theirs';

  @override
  String get ropMessageOptional => 'Message (optional)';

  @override
  String get ropOnlyStaged => 'Only staged changes';

  @override
  String get ropStash => 'Stash';

  @override
  String ropMainlineRevertTitle(String sha) {
    return 'Revert merge $sha';
  }

  @override
  String ropMainlineCherryPickTitle(String sha) {
    return 'Cherry-pick merge $sha';
  }

  @override
  String get ropMainlineRevertBody =>
      'A merge joined two lines of history, so git needs to know which one to keep. The changes that came in from the other parent are undone.';

  @override
  String get ropMainlineCherryPickBody =>
      'A merge has no single set of changes to replay, so git needs a parent to compare it against. The changes that came in from the other parent are applied.';

  @override
  String ropMainlineParent(int n) {
    return 'Parent $n';
  }

  @override
  String get ropMainlineParentFirst => 'the branch merged into';

  @override
  String get ropMainlineParentOther => 'the merged branch';

  @override
  String get shellPrevOpUnfinished =>
      'A previous operation may not have finished';

  @override
  String get wtpChanges => 'CHANGES';

  @override
  String get wtpDiscardAll => 'Discard all changes';

  @override
  String get wtpUnstaged => 'UNSTAGED';

  @override
  String get wtpStageAll => 'Stage all';

  @override
  String get wtpStaged => 'STAGED';

  @override
  String get wtpUnstageAll => 'Unstage all';

  @override
  String wtpAbortTitle(String name) {
    return 'Abort $name?';
  }

  @override
  String wtpAbortBody(String name) {
    return 'The staged resolution is discarded and the repository goes back to where the $name started.';
  }

  @override
  String get wtpAbort => 'Abort';

  @override
  String wtpOpPausedBody(String name) {
    return 'A $name is paused. Review the staged files, then continue it.';
  }

  @override
  String get wtpMergeOpenBody =>
      'A merge is open. Review the staged files, then commit it.';

  @override
  String get wtpBreakPausedBody =>
      'The rebase is paused at a break. Look around, commit or amend if you like, then continue it.';

  @override
  String get wtpRewordRejectedBody =>
      'The rebase is paused: the new message for a commit was rejected, usually by a commit hook. Amend the message yourself, or continue to keep the old one.';

  @override
  String wtpExecFailedBody(String command) {
    return 'The exec step `$command` failed. Fix the problem and commit the fix, then continue — the command is not run again.';
  }

  @override
  String get wtpShowOutput => 'Show output';

  @override
  String get wtpHideOutput => 'Hide output';

  @override
  String wtpContinueOp(String name) {
    return 'Continue $name';
  }

  @override
  String get wtpTreeClean => 'Working tree clean';

  @override
  String get wtpNothingToCommit => 'Nothing to commit';

  @override
  String wtpSectionCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get wtpFileHistory => 'File history';

  @override
  String get wtpBlame => 'Blame';

  @override
  String get wtpDiscardChanges => 'Discard changes';

  @override
  String get wtpFinishOpFirst => 'Finish the operation first';

  @override
  String get wtpFinishOpBody =>
      'Continue or abort it above; committing here would strand the rest of the sequence.';

  @override
  String get wtpMessageEmpty => 'Commit message is empty';

  @override
  String get wtpNothingStaged => 'Nothing staged to commit';

  @override
  String get wtpCommitted => 'Committed';

  @override
  String get wtpCommitFailed => 'Commit failed';

  @override
  String get wtpSummary => 'Summary';

  @override
  String get wtpDescription => 'Description';

  @override
  String get wtpCoauthorsHint => 'Co-authors: Name <email>, Name2 <email2>';

  @override
  String get wtpAmend => 'Amend';

  @override
  String get wtpSign => 'Sign';

  @override
  String get wtpTrailers => 'Trailers';

  @override
  String get wtpSignoff => 'Sign off';

  @override
  String get wtpSignoffTip =>
      'Add a Signed-off-by trailer for the committing identity';

  @override
  String get wtpRefsHint => 'Refs: #12, #34';

  @override
  String get wtpFixesHint => 'Fixes: #12';

  @override
  String get wtpComposerMenu => 'Composer options';

  @override
  String get wtpConventional => 'Conventional Commits';

  @override
  String wtpSubjectLimit(int limit) {
    return 'Subject limit: $limit';
  }

  @override
  String get wtpEditTemplate => 'Message template…';

  @override
  String wtpWrapDescription(int width) {
    return 'Wrap description to $width columns';
  }

  @override
  String get wtpRecentMessages => 'Recent messages';

  @override
  String get wtpNoRecent => 'No recent messages';

  @override
  String get wtpScopeHint => 'scope';

  @override
  String get wtpTypeNone => 'no type';

  @override
  String get wtpBreaking => 'Breaking';

  @override
  String get wtpBreakingTip => 'Marks the subject with ! as a breaking change';

  @override
  String get wtpTemplateUntouched => 'Edit the template first';

  @override
  String get wtpTemplateUntouchedBody =>
      'The message is still exactly the template.';

  @override
  String get wtpTemplateTitle => 'Message template';

  @override
  String wtpTemplateBody(String char) {
    return 'Starts every new commit message in this repository. Lines beginning with $char are guidance and are left out of the commit. Leave it empty to use git\'s commit.template, or a .gitmessage at the repository root.';
  }

  @override
  String get wtpTemplateClear => 'Clear';

  @override
  String get wtpCommit => 'Commit';

  @override
  String get wtpDiscardAllTitle => 'Discard all changes?';

  @override
  String get wtpDiscardAllBody =>
      'This reverts every tracked file to its committed state, dropping staged and unstaged changes. You can undo it.';

  @override
  String wtpDiscardFileTitle(String path) {
    return 'Discard changes to $path?';
  }

  @override
  String get wtpDiscardFileBody =>
      'This reverts the file to its committed state, dropping staged and unstaged changes. You can undo it.';

  @override
  String get wtsWorktrees => 'Worktrees';

  @override
  String get wtsNoWorktrees => 'No worktrees';

  @override
  String get wtsPruneMenu => 'Prune stale worktrees…';

  @override
  String wtsLockTitle(String name) {
    return 'Lock $name';
  }

  @override
  String get wtsReasonOptional => 'Reason (optional)';

  @override
  String get wtsLock => 'Lock';

  @override
  String get wtsLocked => 'Locked';

  @override
  String get wtsPrunable => 'Prunable';

  @override
  String get wtsOpenInTab => 'Open in tab';

  @override
  String get wtsRevealInFinder => 'Reveal in Finder';

  @override
  String get wtsMoveMenu => 'Move…';

  @override
  String get wtsUnlock => 'Unlock';

  @override
  String get wtsLockMenu => 'Lock…';

  @override
  String get wtsRemoveMenu => 'Remove…';

  @override
  String get cdCommit => 'COMMIT';

  @override
  String get cdWip => '‹ WIP';

  @override
  String get cdAuthor => 'Author';

  @override
  String get cdDate => 'Date';

  @override
  String get cdParent => 'Parent';

  @override
  String get cdCoauthored => 'Co-authored';

  @override
  String get cdChangedFiles => 'CHANGED FILES';

  @override
  String get cdCouldNotRead => 'Could not read changes';

  @override
  String get cdNoChanges => 'No changes';

  @override
  String get cdSha => 'SHA';

  @override
  String get cmpTitle => 'COMPARE';

  @override
  String get cmpSwap => 'Swap sides';

  @override
  String get cmpNoDifferences => 'No differences';

  @override
  String get cmpCouldNotRead => 'Could not read the comparison';

  @override
  String get asdTitle => 'Add submodule';

  @override
  String get asdRepoUrl => 'Repository URL';

  @override
  String get asdPath => 'Path';

  @override
  String get asdPathHint => 'folder in this repo';

  @override
  String get asdBranchOptional => 'Branch (optional)';

  @override
  String get asdBranchHint => 'track a branch';

  @override
  String get rdName => 'Name';

  @override
  String get rdUrl => 'URL';

  @override
  String bsResetTitle(String branch, String target) {
    return 'Reset $branch to $target?';
  }

  @override
  String bsResetBody(String branch, String target) {
    return 'This moves local $branch to $target, discarding any commits not on the remote. Uncommitted changes are stashed (undoable).';
  }

  @override
  String get bsResetAndSwitch => 'Reset & switch';

  @override
  String get wvChanges => 'Changes';

  @override
  String get wvChangesSub => 'Working tree · staging · commit';

  @override
  String get rdlgCloneTitle => 'Clone repository';

  @override
  String get rdlgCreateTitle => 'Create repository';

  @override
  String get rdlgFolderName => 'Folder name';

  @override
  String get rdlgFolderHint => 'derived from the URL';

  @override
  String get rdlgDestFolder => 'Destination folder';

  @override
  String get rdlgCloning => 'Cloning…';

  @override
  String get rdlgClone => 'Clone';

  @override
  String get rdlgRepoName => 'Repository name';

  @override
  String get rdlgParentFolder => 'Parent folder';

  @override
  String get rdlgDefaultBranch => 'Default branch';

  @override
  String get rdlgInitReadme => 'Initialise with README.md';

  @override
  String get rdlgAddGitignore => 'Add an empty .gitignore';

  @override
  String get rdlgCreating => 'Creating…';

  @override
  String get rdlgChooseFolder => 'Choose a folder…';

  @override
  String get rdlgBrowse => 'Browse';

  @override
  String get welTitle => 'Welcome to Mergelio';

  @override
  String get welSubtitle => 'Free visual Git client. Get started:';

  @override
  String get welCloneSub => 'From a URL (HTTPS/SSH) into a folder';

  @override
  String get welCreateSub => 'New local repository with README/.gitignore';

  @override
  String get welOpenTitle => 'Open repository';

  @override
  String get welOpenSub => 'Choose an existing folder with .git';

  @override
  String get welUnpin => 'Unpin';

  @override
  String get welPin => 'Pin';

  @override
  String get welRemoveRecent => 'Remove from recents';

  @override
  String get welNotARepo => 'Not a git repository';

  @override
  String get welGitUnavailable => 'Git cannot run';

  @override
  String get gvSearchCommits => 'Search commits…';

  @override
  String get gvAuthorFilter => 'Author…';

  @override
  String get gvPrevMatch => 'Previous (⇧N)';

  @override
  String get gvNextMatch => 'Next (N)';

  @override
  String get gvCloseSearch => 'Close (Esc)';

  @override
  String get gvColumns => 'Columns';

  @override
  String gvUncommittedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Uncommitted changes · $count files',
      one: 'Uncommitted changes · $count file',
    );
    return '$_temp0';
  }

  @override
  String get gvCannotRebaseTitle => 'Cannot rebase onto this commit';

  @override
  String gvCannotRebaseBody(String sha) {
    return 'The commits above $sha include a merge, which a rebase would flatten.';
  }

  @override
  String get gvNothingToRebaseTitle => 'Nothing to rebase';

  @override
  String gvNothingToRebaseBody(String sha) {
    return '$sha is already part of this branch and the plan changes nothing.';
  }

  @override
  String gvResetTitle(String sha) {
    return 'Reset to $sha?';
  }

  @override
  String get gvResetBody =>
      'Moves the current branch to this commit and discards all uncommitted changes. This cannot be undone from disk.';

  @override
  String get gvResetHard => 'Reset --hard';

  @override
  String gvResetMixedTitle(String sha) {
    return 'Reset to $sha?';
  }

  @override
  String get gvResetMixedBody =>
      'Moves the current branch to this commit and keeps the changes as unstaged edits in the working tree. This can be undone.';

  @override
  String get gvResetMixed => 'Reset --mixed';

  @override
  String get ccBranch => 'Branch';

  @override
  String get cpTypeCommand => 'Type a command…';

  @override
  String get termClose => 'Close terminal (⌘`)';

  @override
  String get fiHistory => 'History';

  @override
  String get fiCouldNotLoad => 'Could not load history';

  @override
  String get fiCouldNotBlame => 'Could not blame this file';

  @override
  String get forgePullRequests => 'Pull requests';

  @override
  String get forgeNoPullRequests => 'No open pull requests';

  @override
  String get forgeMergeRequests => 'Merge requests';

  @override
  String get forgeNoMergeRequests => 'No open merge requests';

  @override
  String get forgeIssues => 'Issues';

  @override
  String get forgeNoIssues => 'No open issues';

  @override
  String get forgeRefresh => 'Refresh';

  @override
  String get forgeCouldNotOpenPr =>
      'Could not open the pull request in your browser';

  @override
  String get forgeCouldNotOpenMr =>
      'Could not open the merge request in your browser';

  @override
  String get forgeCouldNotOpenIssue => 'Could not open issue in browser';

  @override
  String get forgeConnectHint =>
      'Without a token: no auto-refresh, 60 requests an hour. Connect in Preferences → Credentials.';

  @override
  String get forgeConnectHintGitlab =>
      'Without a token: no auto-refresh, and a lower shared rate limit. Connect in Preferences → Credentials.';

  @override
  String forgeErrUnauthenticated(String forge) {
    return '$forge rejected the saved token. Reconnect in Preferences.';
  }

  @override
  String forgeErrRateLimited(String forge, String time) {
    return '$forge request limit reached. It resets at $time.';
  }

  @override
  String forgeErrRateLimitedSoon(String forge) {
    return '$forge request limit reached. Try again shortly.';
  }

  @override
  String forgeErrNotVisible(String forge) {
    return 'This repository is not visible to the current $forge token.';
  }

  @override
  String forgeErrOffline(String forge) {
    return 'Could not reach $forge.';
  }

  @override
  String forgeErrServer(String forge, int status) {
    return '$forge answered with an error ($status).';
  }

  @override
  String forgeErrMalformed(String forge) {
    return '$forge sent a response this version could not read.';
  }

  @override
  String forgeAccountTitle(String forge) {
    return '$forge account';
  }

  @override
  String get forgeAccountConnected => 'Connected';

  @override
  String get forgeAccountNotConnected => 'Not connected';

  @override
  String get forgeTokenLabel => 'Personal access token';

  @override
  String get forgeConnect => 'Connect';

  @override
  String get forgeDisconnect => 'Disconnect';

  @override
  String forgeTokenRejected(String forge) {
    return '$forge rejected that token.';
  }

  @override
  String forgeTokenSaved(String forge) {
    return 'Connected to $forge.';
  }

  @override
  String forgeTokenNotKept(String forge) {
    return '$forge accepted the token, but nothing on this system kept it. Set up a git credential helper and try again.';
  }

  @override
  String forgeTokenForgotten(String forge) {
    return '$forge token removed.';
  }

  @override
  String forgeTokenNotForgotten(String forge) {
    return 'Could not remove the $forge token. It may still be stored by git\'s credential helper.';
  }

  @override
  String get forgeRateBenefit =>
      'Without a token GitHub allows 60 requests an hour; with one, 5,000. Opening a repository costs about 23: one request for each list, two for every pull request\'s checks, and one for the repository itself.';

  @override
  String get forgeRateBenefitGitlab =>
      'Without a token, requests to GitLab share a low rate limit with every other anonymous caller. Connecting raises the limit to your own account\'s.';

  @override
  String forgeRateRemaining(int remaining, int limit) {
    return '$remaining of $limit requests left this hour.';
  }

  @override
  String get forgeRefreshInterval => 'Pull and merge request refresh interval';

  @override
  String lhTitleLine(String path, String line) {
    return '$path · line $line';
  }

  @override
  String lhTitleRange(String path, String range) {
    return '$path · lines $range';
  }

  @override
  String get lhLineHistory => 'Line history';

  @override
  String get lhCouldNotLoad => 'Could not load line history';

  @override
  String get lhNoChanges => 'No commit changed these lines';

  @override
  String get ftvFlatList => 'Show as flat list';

  @override
  String get ftvGroupByFolder => 'Group by folder';

  @override
  String get confirmAction => 'Confirm';

  @override
  String get pfScCommandPalette => 'Command palette';

  @override
  String get pfScSearchCommits => 'Search commits';

  @override
  String get pfScNextPrevMatch => 'Next / previous search match';

  @override
  String get pfScPrevNextConflict => 'Previous / next conflict (merge tool)';

  @override
  String get pfScCommit => 'Commit (in composer)';

  @override
  String get pfScCreateBranch => 'Create branch';

  @override
  String get pfScCollapsePanel => 'Collapse left panel';

  @override
  String get pfScToggleTerminal => 'Toggle terminal';

  @override
  String get pfScZoom => 'Zoom in / out';

  @override
  String get pfScResetZoom => 'Reset zoom';

  @override
  String get pfScUndo => 'Undo last action';

  @override
  String get pfScRedo => 'Redo';

  @override
  String get pfScPreferences => 'Preferences';

  @override
  String get pfScCloseDialog => 'Close dialog / cancel';

  @override
  String get pfGenerateSshKey => 'Generate SSH key';

  @override
  String pfAddPassphraseHint(String name) {
    return 'Run ssh-keygen -p -f ~/.ssh/$name to add one.';
  }

  @override
  String get pfGenerateFailed => 'Generate failed';

  @override
  String get pfAuthentication => 'Authentication';

  @override
  String get pfAuthBody =>
      'HTTPS remotes use your system git credential helper; SSH remotes use your SSH agent and keys. Mergelio never stores or reads your passwords or private keys — only public keys are listed here.';

  @override
  String get pfSshKeys => 'SSH KEYS';

  @override
  String get pfGenerateKeyMenu => 'Generate key…';

  @override
  String get pfNoSshKeys => 'No SSH keys found in ~/.ssh';

  @override
  String get pfCopyPublicKey => 'Copy public key';

  @override
  String get pfPublicKeyCopied => 'Public key copied';

  @override
  String get pfThemeJsonCopied => 'Theme JSON copied';

  @override
  String get pfImportTheme => 'Import theme';

  @override
  String get pfPasteThemeJson => 'Paste theme JSON';

  @override
  String get pfInvalidThemeJson => 'Invalid theme JSON';

  @override
  String pfThemeApplied(String name) {
    return 'Applied \"$name\"';
  }

  @override
  String get pfSaveTheme => 'Save theme';

  @override
  String get pfThemeName => 'Theme name';

  @override
  String pfThemeSaved(String name) {
    return 'Saved \"$name\"';
  }

  @override
  String get pfCustomColour => 'Custom colour';

  @override
  String get pfHexHint => 'Hex (e.g. #6E7BFF)';

  @override
  String lgCouldNotOpen(String error) {
    return 'Could not open the log folder: $error';
  }

  @override
  String get lgDiagnosticLogs => 'Diagnostic logs';

  @override
  String get lgNotActive => 'File logging is not active';

  @override
  String get lgReveal => 'Reveal';

  @override
  String get pdEmpty => 'No profiles yet. Add one to set your commit identity.';

  @override
  String get pdUse => 'Use';

  @override
  String pdDeleteTitle(String label) {
    return 'Delete profile $label?';
  }

  @override
  String get pdDeleteBody =>
      'The profile is removed. Any keys it references in the keychain are left untouched.';

  @override
  String get pdAddProfile => 'Add profile';

  @override
  String get pfmNew => 'New profile';

  @override
  String get pfmEdit => 'Edit profile';

  @override
  String get pfmProfileName => 'Profile name';

  @override
  String get pfmProfileNameHint => 'Work, Personal, …';

  @override
  String get pfmDeveloperName => 'Developer name';

  @override
  String get pfmDeveloperNameHint => 'Your name in commits';

  @override
  String get pfmEmail => 'Email';

  @override
  String get fpTitle => 'Create your first profile';

  @override
  String get fpBody =>
      'Every group and repository belongs to a profile. Switching profiles later shows only that profile’s work.';

  @override
  String get fpCreateProfile => 'Create profile';

  @override
  String get mtCurrent => 'Current';

  @override
  String mtCurrentNamed(String into) {
    return 'Current — $into';
  }

  @override
  String get mtIncoming => 'Incoming';

  @override
  String mtIncomingNamed(String branch) {
    return 'Incoming — $branch';
  }

  @override
  String get mtNeedsReview => '⚠ needs review';

  @override
  String get mtResolved => '✓ resolved';

  @override
  String get mtBothAccepted => 'Both accepted ⚠ needs review';

  @override
  String get mtAcceptBoth => 'Accept both';

  @override
  String get mtResult => 'RESULT';

  @override
  String get mtUseEdit => 'Use edit';

  @override
  String get mtAccept => 'Accept';

  @override
  String get mtKeepMine => 'Keep mine';

  @override
  String get mtKeepTheirs => 'Keep theirs';

  @override
  String get mtDeleteFile => 'Delete file';

  @override
  String get mtBinaryConflict =>
      'Binary file — git cannot merge its contents. Keep one version.';

  @override
  String get mtSubmoduleConflict =>
      'Submodule — the branches point it at different commits. Keep one.';

  @override
  String get mtDeletedByUs =>
      'Deleted on this branch, changed by the incoming one.';

  @override
  String get mtDeletedByThem =>
      'Changed on this branch, deleted by the incoming one.';

  @override
  String get mtAddedByUs => 'Added on this branch only.';

  @override
  String get mtAddedByThem => 'Added by the incoming branch only.';

  @override
  String get mtBothDeleted => 'Deleted on both branches.';

  @override
  String mtConflictCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicts',
      one: '$count conflict',
    );
    return '$_temp0';
  }

  @override
  String mtConflictPosition(int current, int total) {
    return 'Conflict $current of $total';
  }

  @override
  String get mtPrevConflict => 'Previous conflict (⌥↑)';

  @override
  String get mtNextConflict => 'Next conflict (⌥↓)';

  @override
  String get rbPick => 'keep this commit as it is';

  @override
  String get rbReword => 'keep this commit, change its message';

  @override
  String get rbSquash => 'merge into the commit above, keep both messages';

  @override
  String get rbFixup => 'merge into the commit above, drop its message';

  @override
  String get rbDrop => 'remove this commit entirely';

  @override
  String get rbExec =>
      'run a shell command here; if it fails, the rebase pauses';

  @override
  String get rbBreak =>
      'pause here so you can look around or amend, then continue';

  @override
  String get rbPresetAsIs => 'Move commits as-is';

  @override
  String get rbPresetSquashAll => 'Squash into one commit';

  @override
  String get rbPresetSquashKeepFirst => 'Squash, keep first message';

  @override
  String rbSummaryAsIs(int count) {
    return 'Replay all $count commits on the new base. History keeps its shape.';
  }

  @override
  String rbSummarySquashAll(int count) {
    return 'Combine all $count into one commit; all messages are kept, one after another.';
  }

  @override
  String rbSummarySquashKeepFirst(int count) {
    return 'Combine all $count into one commit; only the first message is kept.';
  }

  @override
  String get rbTitle => 'Interactive rebase';

  @override
  String rbCommitCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits',
      one: '$count commit',
    );
    return '$_temp0';
  }

  @override
  String rbCommitCountOnto(int count, String onto) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits onto $onto',
      one: '$count commit onto $onto',
    );
    return '$_temp0';
  }

  @override
  String get rbStart => 'Start rebase';

  @override
  String get rbNeedsTwo => 'Needs at least 2 commits.';

  @override
  String get rbCustomize => 'Customize per commit';

  @override
  String get rbCustomizeHint =>
      'Pick an action for each commit, or drag to reorder them.';

  @override
  String get rbAutosquash => 'Fold fixup commits into their targets';

  @override
  String rbAutosquashHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count fixup!/squash! commits found — each moves under the commit it names.',
      one:
          '1 fixup!/squash! commit found — it moves under the commit it names.',
    );
    return '$_temp0';
  }

  @override
  String rbFoldsInto(String target) {
    return '↳ into $target';
  }

  @override
  String get rbUpdateRefs => 'Move stacked branches too';

  @override
  String rbUpdateRefsHint(String branches) {
    return '$branches point at these commits and will follow them.';
  }

  @override
  String get rbAddExec => 'Add exec step';

  @override
  String get rbAddBreak => 'Add break';

  @override
  String get rbExecFieldHint => 'Shell command, e.g. flutter test';

  @override
  String get rbRemoveStep => 'Remove step';

  @override
  String get rbExecConfirmTitle => 'Run these commands?';

  @override
  String rbExecConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'These $count commands run in the repository between commits, exactly as written. If one fails, the rebase pauses there.',
      one: 'This command runs in the repository between commits, exactly as written. If it fails, the rebase pauses there.',
    );
    return '$_temp0';
  }

  @override
  String get rbExecConfirmRun => 'Run rebase';

  @override
  String get dlgEditCommitMessage => 'Edit commit message';

  @override
  String dlgUnsavedOne(String path) {
    return '$path has changes that are not on disk.';
  }

  @override
  String get dlgUnsavedMany => 'These files have changes that are not on disk:';

  @override
  String fteConflictBody(String name) {
    return 'Something else wrote $name while it was open here. Saving replaces those changes with this text.';
  }

  @override
  String get fteCouldNotOpen => 'Could not open this file';

  @override
  String get fteNoResults => 'No results';

  @override
  String get fteFind => 'Find';

  @override
  String get fteReplaceWith => 'Replace with';

  @override
  String get fteMatchCase => 'Match case';

  @override
  String get ftePreviousMatch => 'Previous match';

  @override
  String get fteNextMatch => 'Next match';

  @override
  String get fteReplaceThis => 'Replace this match';

  @override
  String get fteReplaceAll => 'Replace all';

  @override
  String get diffEditingWorkingTree =>
      'Editing the working tree — saved changes stay unstaged';

  @override
  String get diffStageSelectedLines => 'Stage selected lines';

  @override
  String get diffUnstageSelectedLines => 'Unstage selected lines';

  @override
  String get diffDiscardSelectedLines => 'Discard selected lines';

  @override
  String diffUnsavedBody(String path) {
    return 'What you typed in $path has not been written to the working tree.';
  }

  @override
  String get diffUncommittedWorkingTree => 'Uncommitted changes · working tree';

  @override
  String get diffStageFile => 'Stage file';

  @override
  String get diffUnstageFile => 'Unstage file';

  @override
  String get diffShowChangesOnly => 'Show changes only';

  @override
  String get diffShowWholeFile => 'Show whole file';

  @override
  String get diffMoreActions => 'More actions';

  @override
  String get diffViewInline => 'Inline';

  @override
  String get diffViewSplit => 'Split';

  @override
  String get diffCouldNotLoad => 'Could not load diff';

  @override
  String get lfsBadge => 'LFS';

  @override
  String get lfsBadgeTooltip => 'Stored with Git LFS';

  @override
  String get lfsCardModified => 'LFS object';

  @override
  String get lfsCardAdded => 'Added LFS object';

  @override
  String get lfsCardDeleted => 'Deleted LFS object';

  @override
  String get lfsCardMovedIn => 'Moved into LFS';

  @override
  String get lfsCardMovedOut => 'Moved out of LFS';

  @override
  String get lfsDownloaded => 'Downloaded';

  @override
  String get lfsNotDownloaded => 'Not downloaded';

  @override
  String get lfsToolMissing =>
      'git-lfs isn\'t installed — files show as pointers';

  @override
  String get lfsMismatch => 'Tracked by LFS but stored as a regular blob';

  @override
  String get lfsShowTextDiff => 'Show text diff';

  @override
  String get lfsBannerText =>
      'This repository stores files with Git LFS, but git-lfs isn\'t installed. Files show as pointers until you install it.';

  @override
  String get lfsBannerDismiss => 'Dismiss';

  @override
  String get lfsInstallHomebrew =>
      'Install it with `brew install git-lfs`, then run `git lfs install`.';

  @override
  String get lfsInstallGitForWindows =>
      'Git for Windows includes it — reinstall with Git LFS selected, then run `git lfs install`.';

  @override
  String get lfsInstallPackageManager =>
      'Install git-lfs with your package manager, then run `git lfs install`.';

  @override
  String get lfsOpPull => 'Pull LFS files';

  @override
  String get lfsOpFetchAll => 'Fetch all LFS objects';

  @override
  String get lfsOpPrune => 'Prune LFS objects…';

  @override
  String lfsPointerStrip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count LFS files are not downloaded',
      one: '1 LFS file is not downloaded',
    );
    return '$_temp0';
  }

  @override
  String get lfsDownload => 'Download';

  @override
  String get lfsNoRemote => 'No remote to download from';

  @override
  String get lfsDownloadUnsafePath =>
      'This file\'s name cannot be downloaded on its own — use Pull LFS files.';

  @override
  String get lfsPruneNothing => 'Nothing to prune';

  @override
  String get lfsPruneUnreadable => 'Could not preview the prune';

  @override
  String get lfsPruneTitle => 'Prune LFS objects';

  @override
  String lfsPruneBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove $count downloaded LFS objects?',
      one: 'Remove 1 downloaded LFS object?',
    );
    return '$_temp0 They are not needed by recent commits and can be downloaded again.';
  }

  @override
  String get lfsPruneConfirm => 'Prune';

  @override
  String lfsTrackExtension(String pattern) {
    return 'Track $pattern with LFS';
  }

  @override
  String get lfsTrackFile => 'Track this file with LFS';

  @override
  String get lfsUntrack => 'Stop tracking with LFS…';

  @override
  String get lfsUntrackTitle => 'Stop tracking with LFS';

  @override
  String get lfsUntrackBody =>
      'Pick the pattern to remove from .gitattributes. Files already stored in LFS stay there.';

  @override
  String lfsConvertOffer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count committed files match but are not in LFS',
      one: '1 committed file matches but is not in LFS',
    );
    return '$_temp0';
  }

  @override
  String get lfsConvertAction => 'Convert…';

  @override
  String get lfsConvertTitle => 'Convert files to LFS';

  @override
  String get lfsConvertBody =>
      'This stages these files as LFS pointers, together with the .gitattributes change that makes them so, including any edits you have in them. Nothing is committed.';

  @override
  String lfsConvertMore(int count) {
    return 'and $count more';
  }

  @override
  String get lfsConvertConfirm => 'Stage as LFS';

  @override
  String get lfsPushHookTitle => 'LFS hooks are not installed';

  @override
  String get lfsPushHookBody =>
      'This repository stores files with Git LFS, but pushing from here would upload only pointers — the LFS hooks are not installed.';

  @override
  String get lfsPushInstallAndPush => 'Install LFS hooks and push';

  @override
  String get lfsPushHookNotRunnable =>
      'The pre-push hook exists, but git will not run it because the file is not executable. Nothing was pushed.';

  @override
  String get lfsLockChipYou => 'You';

  @override
  String lfsLockTooltip(String owner, String age) {
    return 'Locked by $owner · $age';
  }

  @override
  String get lfsLockFile => 'Lock file';

  @override
  String get lfsUnlockFile => 'Unlock file';

  @override
  String get lfsForceUnlock => 'Force unlock…';

  @override
  String get lfsForceUnlockTitle => 'Break someone else\'s lock';

  @override
  String lfsForceUnlockBody(String owner, String age) {
    return 'Locked by $owner ($age). Breaking the lock does not stop them from pushing their changes, and they may lose work.';
  }

  @override
  String get lfsForceUnlockConfirm => 'Break lock';

  @override
  String get lfsLocksSection => 'Locks';

  @override
  String get lfsLocksYours => 'Yours';

  @override
  String get lfsLocksOthers => 'Others';

  @override
  String get lfsLocksRefresh => 'Refresh';

  @override
  String get lfsLocksStale =>
      'Couldn\'t refresh locks — showing the last known list';

  @override
  String lfsLocksMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more',
      one: 'and $count more',
    );
    return '$_temp0';
  }

  @override
  String lfsLocksMoreAtLeast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count+ more',
      one: 'and $count+ more',
    );
    return '$_temp0';
  }

  @override
  String lfsLockTooltipNoAge(String owner) {
    return 'Locked by $owner';
  }

  @override
  String lfsForceUnlockBodyNoAge(String owner) {
    return 'Locked by $owner. Breaking the lock does not stop them from pushing their changes, and they may lose work.';
  }

  @override
  String lfsLocksRefreshedAt(String age) {
    return 'Last refreshed: $age';
  }

  @override
  String get lfsLocksUnsupported =>
      'This repository\'s server doesn\'t support file locks.';

  @override
  String get lfsPushLockedTitle => 'Files locked by someone else';

  @override
  String get lfsPushLockedBody =>
      'These files are locked by someone else. Pushing changes to them may overwrite their work.';

  @override
  String get lfsPushAnyway => 'Push anyway';

  @override
  String get lfsPushToolTitle => 'git-lfs is not installed';

  @override
  String get lfsPushToolBody =>
      'This repository stores files with Git LFS. Pushing without git-lfs uploads pointers without their content.';

  @override
  String get diffCouldNotStage => 'Could not stage';

  @override
  String get diffCouldNotUnstage => 'Could not unstage';

  @override
  String get diffCouldNotDiscard => 'Could not discard';

  @override
  String get diffStageHunk => 'Stage hunk';

  @override
  String get diffUnstageHunk => 'Unstage hunk';

  @override
  String get diffDiscardHunk => 'Discard hunk';

  @override
  String get diffUnstagedLabel => 'Unstaged';

  @override
  String get diffStagedLabel => 'Staged';

  @override
  String get fepOpenAFile => 'Open a file to edit it';

  @override
  String get fepDeletedOnDisk => 'Deleted on disk — saving is disabled';

  @override
  String get pnpNewFileMenu => 'New file…';

  @override
  String get pnpNewFolderMenu => 'New folder…';

  @override
  String get pnpRenameMenu => 'Rename…';

  @override
  String get pnpDeleteMenu => 'Delete…';

  @override
  String get pnpStage => 'Stage';

  @override
  String get pnpUnstage => 'Unstage';

  @override
  String get pnpDiscardMenu => 'Discard changes…';

  @override
  String get pnpShowHistory => 'Show history';

  @override
  String get pnpRevealInFinder => 'Reveal in Finder';

  @override
  String get pnpShowInExplorer => 'Show in Explorer';

  @override
  String get pnpOpenContainingFolder => 'Open containing folder';

  @override
  String get pnpNewFile => 'New file';

  @override
  String get pnpNewFolder => 'New folder';

  @override
  String get pnpDeleteFolderBody =>
      'The folder and everything in it is removed from disk, not just from git.';

  @override
  String get pnpDeleteFileBody =>
      'The file is removed from disk, not just from git.';

  @override
  String get pnpDiscardUntrackedBody =>
      'The file is untracked, so discarding deletes it.';

  @override
  String get pnpDiscardTrackedBody =>
      'The file goes back to what it was at the last commit.';

  @override
  String get pnpCouldNotOpenFileManager => 'Could not open the file manager';

  @override
  String get pnpOperationFailed => 'Operation failed';

  @override
  String pnpMore(int count) {
    return '…$count more';
  }

  @override
  String get pnpProject => 'Project';

  @override
  String get pnpShowIgnored => 'Show ignored files';

  @override
  String get pnpHideIgnored => 'Hide ignored files';

  @override
  String get prefsTabUpdates => 'Updates';

  @override
  String updateBannerAvailable(String version) {
    return 'Mergelio $version is available';
  }

  @override
  String get updateBannerDownloading => 'Downloading update…';

  @override
  String get updateBannerReady => 'Update ready to install';

  @override
  String get updateActionDownload => 'Download';

  @override
  String get updateActionInstall => 'Install and restart';

  @override
  String get updateActionNotes => 'Release notes';

  @override
  String get updateActionSkip => 'Skip this version';

  @override
  String get updateActionLater => 'Later';

  @override
  String get updateBlockedBusy => 'Waiting for the current operation to finish';

  @override
  String get updateManualNone => 'Mergelio is up to date';

  @override
  String get updateManualFailed => 'Could not check for updates';

  @override
  String get updateLinuxHint => 'Install it through your package manager';

  @override
  String get updateConsentTitle => 'Check for updates?';

  @override
  String get updateConsentBody =>
      'Mergelio can check GitHub once a day for a new release. No account, no identifiers, nothing about your repositories is sent.';

  @override
  String get updateConsentYes => 'Check for updates';

  @override
  String get updateConsentNo => 'Don\'t check';

  @override
  String updatePrefsCurrent(String version) {
    return 'Current version: $version';
  }

  @override
  String get updatePrefsAuto => 'Check for updates automatically';

  @override
  String get updatePrefsCheckNow => 'Check now';

  @override
  String updatePrefsLastCheck(String when) {
    return 'Last checked: $when';
  }

  @override
  String get updatePrefsNever => 'never';

  @override
  String get askpassTitle => 'Authentication required';

  @override
  String get askpassFallback => 'Enter your credentials';

  @override
  String get askpassSubmit => 'OK';

  @override
  String get askpassYes => 'Yes';

  @override
  String get askpassNo => 'No';

  @override
  String get forgeAgoNow => 'now';

  @override
  String forgeAgoMinutes(int n) {
    return '${n}m';
  }

  @override
  String forgeAgoHours(int n) {
    return '${n}h';
  }

  @override
  String forgeAgoDays(int n) {
    return '${n}d';
  }

  @override
  String get bisectAwaitingGood => 'Bisecting. Mark a commit you know is good.';

  @override
  String bisectRevisionsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count revisions left',
      one: '$count revision left',
    );
    return '$_temp0';
  }

  @override
  String bisectStepsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'about $count steps',
      one: 'about $count step',
    );
    return '$_temp0';
  }

  @override
  String bisectTesting(String sha) {
    return 'Testing $sha';
  }

  @override
  String get bisectGood => 'Good';

  @override
  String get bisectBad => 'Bad';

  @override
  String get bisectSkip => 'Skip';

  @override
  String get bisectReset => 'Reset bisect';

  @override
  String get bisectLog => 'Log';

  @override
  String get bisectLogFailed => 'The bisect log could not be read.';

  @override
  String get bisectLogEmpty => 'No verdicts recorded yet.';

  @override
  String get bisectFirstBadTitle => 'First bad commit';

  @override
  String get bisectJumpToCommit => 'Jump to commit';

  @override
  String get bisectCopySha => 'Copy SHA';

  @override
  String get bisectCopyFixup => 'Copy fixup!';

  @override
  String get bisectRevertCommit => 'Revert this commit';

  @override
  String get bisectRevertNotLoaded =>
      'This commit is outside the loaded history. Scroll the graph to load it, then revert it from its row.';

  @override
  String get bisectPillGood => 'good';

  @override
  String get bisectPillBad => 'bad';

  @override
  String get bisectPillSkip => 'skip';

  @override
  String get bisectMenuStart => 'Start bisect from here';

  @override
  String get bisectMenuGood => 'Mark as good';

  @override
  String get bisectMenuBad => 'Mark as bad';

  @override
  String get bisectMenuSkip => 'Skip this commit';

  @override
  String get bisectQuitTitle => 'Bisect in progress';

  @override
  String get bisectQuitBody =>
      'Quitting, or closing this repository, leaves it on a detached HEAD. Reset the bisect first?';

  @override
  String get bisectQuitAnyway => 'Continue anyway';

  @override
  String get bisectNoMarks => 'Bisecting. Mark a bad commit to begin.';

  @override
  String get bisectUnreadable => 'Bisect state could not be read';

  @override
  String get bisectRun => 'Run a command…';

  @override
  String get bisectRunTitle => 'Run a command to bisect';

  @override
  String get bisectRunHint => 'Command to test each commit';

  @override
  String get bisectRunWillExecute => 'Will run:';

  @override
  String get bisectRunTreeWarning =>
      'A command that modifies tracked files will break the run.';

  @override
  String get bisectRunStart => 'Run';

  @override
  String bisectRunning(String command) {
    return 'Running $command';
  }

  @override
  String get bisectRunExhausted =>
      'Every remaining commit was skipped, so git cannot narrow this further.';

  @override
  String get bisectRunUnrunnable =>
      'Your command could not be run. Check that it exists and is executable.';

  @override
  String get bisectRunTreeDirtied =>
      'Your command modified tracked files, so git could not check out the next commit.';

  @override
  String get bisectRunCancelled =>
      'Run cancelled. The marks recorded so far are kept.';

  @override
  String get mntTitle => 'Repository maintenance';

  @override
  String get mntPaletteOpen => 'Repository maintenance…';

  @override
  String get mntStorage => 'Storage';

  @override
  String mntStorageTotal(String size) {
    return 'Git data: $size';
  }

  @override
  String get mntPacks => 'Packs';

  @override
  String mntPackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count packs',
      one: '1 pack',
    );
    return '$_temp0';
  }

  @override
  String get mntLoose => 'Loose objects';

  @override
  String mntLooseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objects',
      one: '1 object',
    );
    return '$_temp0';
  }

  @override
  String get mntLfs => 'LFS objects';

  @override
  String get mntOther => 'Other git data';

  @override
  String get mntStorageNote => 'Files in the working tree are not counted.';

  @override
  String mntReadFailed(String error) {
    return 'Could not read this: $error';
  }

  @override
  String get mntBlobs => 'Largest files in history';

  @override
  String get mntBlobsIntro =>
      'Scans every object in the repository\'s history. On a large repository this can take several minutes.';

  @override
  String get mntScan => 'Scan';

  @override
  String get mntRescan => 'Rescan';

  @override
  String get mntScanning => 'Scanning history…';

  @override
  String mntScannedAt(String when) {
    return 'Scanned $when';
  }

  @override
  String get mntScanStale =>
      'Out of date: branches or tags have moved since this scan';

  @override
  String mntScanFailed(String error) {
    return 'Scan failed: $error';
  }

  @override
  String get mntNoBlobs => 'No files in history.';

  @override
  String get mntNoPath => '(no path)';

  @override
  String get mntNoCommit => 'not in the history of any branch or tag';

  @override
  String get mntBranches => 'Branches';

  @override
  String mntMergedInto(String trunk, int days) {
    return 'Merged into $trunk, or not touched for $days days, or their upstream is gone.';
  }

  @override
  String get mntNoBranches => 'No merged or stale branches.';

  @override
  String get mntTagMerged => 'merged';

  @override
  String get mntTagStale => 'stale';

  @override
  String get mntTagGone => 'upstream gone';

  @override
  String mntHeldBy(String path) {
    return 'checked out in $path';
  }

  @override
  String get mntSelectAll => 'Select all';

  @override
  String mntDeleteSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count branches',
      one: 'Delete 1 branch',
    );
    return '$_temp0';
  }

  @override
  String get mntDeleteTitle => 'Delete branches';

  @override
  String mntDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count branches?',
      one: 'Delete 1 branch?',
    );
    return '$_temp0 Undo puts them back.';
  }

  @override
  String get mntDeleteForce =>
      'These are not merged and will be force-deleted. Their commits stay reachable only through the reflog:';

  @override
  String get mntDeleteConfirm => 'Delete';

  @override
  String get mntWorktrees => 'Worktrees';

  @override
  String mntPrunable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count worktrees point at missing directories',
      one: '1 worktree points at a missing directory',
    );
    return '$_temp0';
  }

  @override
  String get mntNoPrunable => 'Nothing to prune.';

  @override
  String get mntPrune => 'Prune…';

  @override
  String get mntReflog => 'Reflog';

  @override
  String mntReflogExpiry(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The next gc would expire $count reflog entries.',
      one: 'The next gc would expire 1 reflog entry.',
      zero: 'The next gc would not expire any reflog entries.',
    );
    return '$_temp0';
  }

  @override
  String get mntHousekeeping => 'Housekeeping';

  @override
  String get mntHousekeepingHint =>
      'Repacks objects and removes unreachable ones git considers expired. Mergelio never runs this on its own.';

  @override
  String get mntRunGc => 'Run gc';

  @override
  String get mntRunMaintenance => 'Run maintenance';

  @override
  String get mntGcTitle => 'Run git gc?';

  @override
  String get mntGcBody =>
      'git gc repacks the repository and deletes unreachable objects older than its expiry settings. It can take a while and can be cancelled from the status bar.';

  @override
  String get mntMaintenanceTitle => 'Run git maintenance?';

  @override
  String get mntMaintenanceBody =>
      'Runs the maintenance tasks this repository\'s config enables (gc when none are set). It can take a while and can be cancelled from the status bar.';

  @override
  String get mntRun => 'Run';

  @override
  String mntSizeChange(String before, String after) {
    return 'Git data: $before → $after';
  }

  @override
  String mntHeldByPrunable(String path) {
    return 'checked out in $path, which no longer exists. Prune worktrees first.';
  }

  @override
  String get mntShowCommit => 'Show this commit in the graph';

  @override
  String get bdSideBySide => 'Side by side';

  @override
  String get bdSwipe => 'Swipe';

  @override
  String get bdOnionSkin => 'Onion skin';

  @override
  String get bdDifference => 'Difference';

  @override
  String get bdBefore => 'Before';

  @override
  String get bdAfter => 'After';

  @override
  String get bdTooLarge => 'Too large to preview';

  @override
  String get bdUnavailable => 'Preview unavailable';

  @override
  String get bdNothingToShow => 'Nothing to show on either side';

  @override
  String bdHexPreview(int count) {
    return 'First $count bytes';
  }

  @override
  String get stTitle => 'STASH';

  @override
  String stBase(String sha) {
    return 'Made on $sha';
  }

  @override
  String get stUntrackedFiles => 'UNTRACKED FILES';

  @override
  String get stNoChanges => 'This stash holds no changes';

  @override
  String get stCouldNotRead => 'Could not read the stash';

  @override
  String get stRename => 'Rename';

  @override
  String get stRenameMenu => 'Rename…';

  @override
  String stRenameTitle(String ref) {
    return 'Rename $ref';
  }

  @override
  String get stRenameLabel => 'Message';

  @override
  String get stBranch => 'Branch…';

  @override
  String get stBranchMenu => 'Branch from stash…';

  @override
  String stBranchTitle(String ref) {
    return 'Branch from $ref';
  }

  @override
  String get stBranchLabel => 'New branch name';

  @override
  String get stBranchConfirm => 'Create branch';

  @override
  String get stApplyFile => 'Apply to working tree';

  @override
  String get stApplyHunk => 'Apply hunk';

  @override
  String get ropKeepIndex => 'Keep staged changes in place';

  @override
  String get ropIncludeUntracked => 'Include untracked files';

  @override
  String get ropStashFiles => 'Files to stash';

  @override
  String get ropNothingToStash => 'Nothing to stash';

  @override
  String get rvTitle => 'REVIEW';

  @override
  String get rvPickTitle => 'Review branches';

  @override
  String get rvBase => 'Base';

  @override
  String get rvHead => 'Head';

  @override
  String get rvSideHint => 'Branch, tag, remote branch or commit';

  @override
  String get rvWorktreeNote =>
      'A worktree is read at its last commit; its uncommitted edits are not part of the review.';

  @override
  String rvNotACommit(String ref) {
    return '\"$ref\" is not a commit in this repository';
  }

  @override
  String get rvOpen => 'Open review';

  @override
  String get rvSwap => 'Swap base and head';

  @override
  String get rvModeThreeDot => 'Since branch point';

  @override
  String get rvModeTwoDot => 'Tip to tip';

  @override
  String rvThreeDotCaption(String range, String head, String base) {
    return '$range: what $head changed since it branched from $base, as a pull request shows it.';
  }

  @override
  String rvTwoDotCaption(String range, String base, String head) {
    return '$range: every difference between the tips of $base and $head, including changes made only on $base.';
  }

  @override
  String rvAheadBehind(String head, int ahead, int behind, String base) {
    return '$head is $ahead ahead, $behind behind $base';
  }

  @override
  String rvFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String rvViewedCount(int viewed, int total) {
    return '$viewed of $total viewed';
  }

  @override
  String get rvViewed => 'Viewed';

  @override
  String rvCommits(int count) {
    return 'COMMITS ($count)';
  }

  @override
  String rvCommitsTruncated(int count) {
    return 'Showing the newest $count';
  }

  @override
  String get rvNoCommits => 'Head has no commits that base lacks';

  @override
  String get rvFiles => 'FILES';

  @override
  String rvNoMergeBase(String base, String head) {
    return '$base and $head share no history, so there is no branch point to read from. Tip to tip still shows how they differ.';
  }

  @override
  String get rvUseTwoDot => 'Show tip to tip';

  @override
  String get rvNoChanges => 'No file changes';

  @override
  String get rvCouldNotRead => 'Could not read the review';

  @override
  String get rvCouldNotReadFile => 'Could not read this file\'s diff';

  @override
  String get rvCollapseAll => 'Collapse all';

  @override
  String get rvExpandAll => 'Expand all';

  @override
  String rvLargeDiff(int count) {
    return 'Large diff ($count lines). Expand to show it.';
  }

  @override
  String get rvBinary =>
      'Binary or LFS file. Open it in the diff viewer to compare.';

  @override
  String get rvNoContentChange => 'Renamed without content changes';

  @override
  String get rvOpenInDiff => 'Open in diff viewer';

  @override
  String get rvFileHistoryAtHead => 'File history at head';

  @override
  String get rvBlameAtHead => 'Blame at head';

  @override
  String get rvExport => 'Export patches';

  @override
  String get rvSavePatches => 'Save as patch files…';

  @override
  String get rvCopyPatch => 'Copy as patch';

  @override
  String rvPatchesSaved(int count, String dir) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saved $count patches to $dir',
      one: 'Saved 1 patch to $dir',
    );
    return '$_temp0';
  }

  @override
  String get rvPatchCopied => 'Patch copied';

  @override
  String get rvExportFailed => 'Could not export patches';

  @override
  String get rvOpenPr => 'Open pull request';

  @override
  String get rvOpenMr => 'Open merge request';

  @override
  String get rvKindBranch => 'branch';

  @override
  String get rvKindRemote => 'remote';

  @override
  String get rvKindTag => 'tag';

  @override
  String get rvKindWorktree => 'worktree';

  @override
  String get rvReviewAgainstCurrent => 'Review against current';

  @override
  String get rvPaletteReview => 'Review branches…';

  @override
  String rvNoOpenPr(String branch) {
    return 'No single open pull request for $branch';
  }

  @override
  String rvNoOpenMr(String branch) {
    return 'No single open merge request for $branch';
  }

  @override
  String get rvPrLookupFailed => 'Could not look up the pull request';

  @override
  String get rvMrLookupFailed => 'Could not look up the merge request';

  @override
  String get sigGood => 'Verified signature';

  @override
  String get sigUntrusted => 'Valid, untrusted key';

  @override
  String get sigExpired => 'Expired signature';

  @override
  String get sigExpiredKey => 'Expired key';

  @override
  String get sigRevoked => 'Revoked key';

  @override
  String get sigBad => 'Bad signature';

  @override
  String get sigUnverifiable => 'Cannot verify signature';

  @override
  String get sigNone => 'Not signed';

  @override
  String get sigShowDetails => 'Show signature details';

  @override
  String get sigHideDetails => 'Hide signature details';

  @override
  String get sigSigner => 'Signer';

  @override
  String get sigKey => 'Key';

  @override
  String get sigFingerprint => 'Fingerprint';

  @override
  String get sigPrimaryKey => 'Primary key';

  @override
  String get sigTrust => 'Trust';

  @override
  String get sigFormat => 'Format';

  @override
  String get sigUnknownSigner => 'Unknown signer';

  @override
  String get sigHintNoAllowedSigners =>
      'The signature matches the key, but git names an SSH signer only when gpg.ssh.allowedSignersFile is set.';

  @override
  String sigHintKeyNotAllowed(String path) {
    return 'This SSH key is not listed in the allowed signers file ($path).';
  }

  @override
  String get sigHintMissingKey =>
      'The signer\'s public key is not available on this machine, so the signature could not be checked.';

  @override
  String sigTag(String name) {
    return 'Tag $name';
  }

  @override
  String get sigPaletteAudit => 'Check signatures…';

  @override
  String get sigAuditTitle => 'Signature check';

  @override
  String get sigAuditBase => 'Since';

  @override
  String get sigAuditBaseHint => 'branch, tag or commit';

  @override
  String get sigAuditRun => 'Check';

  @override
  String sigAuditRange(String range) {
    return 'Checks $range: commits reachable from HEAD but not from the base.';
  }

  @override
  String sigAuditAllVerified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count commits have a verified signature',
      one: 'The commit has a verified signature',
    );
    return '$_temp0';
  }

  @override
  String sigAuditSummary(int count, int unverified) {
    String _temp0 = intl.Intl.pluralLogic(
      unverified,
      locale: localeName,
      other: '$unverified commits of $count lack a verified signature',
      one: '$unverified commit of $count lacks a verified signature',
    );
    return '$_temp0';
  }

  @override
  String get sigAuditEmpty => 'No commits in this range';

  @override
  String sigAuditTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Only the latest $count commits were checked.',
      one: 'Only the latest commit was checked.',
    );
    return '$_temp0';
  }

  @override
  String get sigAuditFailed => 'Could not check signatures';

  @override
  String sigHintSignersUnreadable(String path) {
    return 'The allowed signers file ($path) could not be opened, so git cannot name the signer.';
  }

  @override
  String sigHintVerifierMissing(String program) {
    return 'git could not start $program, so nothing was checked. Install it or point git at it (gpg.program, gpg.ssh.program).';
  }

  @override
  String sigMoreTags(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Verify $count more tags',
      one: 'Verify 1 more tag',
    );
    return '$_temp0';
  }

  @override
  String get sigHintSshUnconfigured =>
      'git verifies SSH signatures only when gpg.ssh.allowedSignersFile points at an allowed signers file. Set it to check SSH-signed commits.';

  @override
  String get hkTitle => 'Git hooks';

  @override
  String get hkPaletteOpen => 'Git hooks…';

  @override
  String get hkDir => 'Hooks directory';

  @override
  String hkCustomPath(String path) {
    return 'Set by core.hooksPath: $path';
  }

  @override
  String hkManaged(String tool) {
    return 'Managed by $tool — it may overwrite changes made here when it reinstalls its hooks.';
  }

  @override
  String get hkEmpty => 'No hooks in this repository.';

  @override
  String get hkStateActive => 'Active';

  @override
  String get hkStateDisabled => 'Disabled';

  @override
  String get hkStateSample => 'Sample';

  @override
  String get hkEdit => 'Edit';

  @override
  String get hkUseSample => 'Use sample';

  @override
  String get hkEnable => 'Enable — git runs this hook';

  @override
  String get hkDisable => 'Disable — git skips this hook';

  @override
  String hkEditorTitle(String hook) {
    return 'Edit the $hook hook';
  }

  @override
  String get hkSkipHooks => 'Skip hooks';

  @override
  String get hkSkipArmed => 'Next commit skips hooks (--no-verify)';

  @override
  String get hkSkipDisarm => 'Run hooks again';

  @override
  String hkRejectedTitle(String hook) {
    return 'The $hook hook rejected the commit';
  }

  @override
  String hkOutputFrom(String hook) {
    return 'Output from $hook';
  }

  @override
  String get hkNoOutput => 'The hook printed nothing.';

  @override
  String get hkMessageKept => 'Your message was kept.';

  @override
  String get hkManage => 'Manage hooks…';

  @override
  String get hkSkipNext => 'Skip hooks for next commit';

  @override
  String get hkLinkedNoToggle =>
      'Linked to a file elsewhere — change its mode there, so the change is not made behind your back.';

  @override
  String hkChangeFailed(String hook) {
    return 'Could not change the $hook hook';
  }

  @override
  String get hkFailNotFound => 'The hook file is not there any more.';

  @override
  String get hkFailExists => 'A hook with this name already exists.';

  @override
  String get hkFailOutside =>
      'The hook links to a file outside the repository, so it is not changed from here.';

  @override
  String get hkFailLinked =>
      'The hook links to a file elsewhere; change that file\'s mode instead.';

  @override
  String get hkRewordSkip => 'Reword without hooks';

  @override
  String get dashTitle => 'Dashboard';

  @override
  String get dashToolbarTooltip =>
      'Every repository in this group at a glance (⌘⇧D)';

  @override
  String dashRepoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count repositories',
      one: '1 repository',
    );
    return '$_temp0';
  }

  @override
  String get dashFetchAll => 'Fetch all';

  @override
  String get dashFetchAllTooltip =>
      'Fetch every repository in this group, a few at a time';

  @override
  String get dashPullAll => 'Pull fast-forwardable';

  @override
  String get dashPullAllTooltip =>
      'Fast-forward each clean branch that is only behind its upstream. Nothing is merged or committed; the rest are listed with the reason.';

  @override
  String get dashRefresh => 'Refresh';

  @override
  String get dashEmpty => 'No repositories in this group.';

  @override
  String get dashDetached => 'detached HEAD';

  @override
  String get dashUnborn => 'no commits yet';

  @override
  String get dashNoUpstream => 'no upstream';

  @override
  String get dashUpstreamGone => 'upstream gone';

  @override
  String dashUpstreamGoneTooltip(String upstream) {
    return '$upstream no longer exists on the remote';
  }

  @override
  String dashAheadBehindTooltip(int ahead, int behind, String upstream) {
    return '$ahead ahead, $behind behind $upstream';
  }

  @override
  String dashChanged(int count) {
    return '$count changed';
  }

  @override
  String dashConflicted(int count) {
    return '$count conflicted';
  }

  @override
  String dashUntracked(int count) {
    return '$count untracked';
  }

  @override
  String dashStashes(int count) {
    return '$count stashed';
  }

  @override
  String get dashClean => 'clean';

  @override
  String dashFetchedAgo(String age) {
    return 'fetched $age';
  }

  @override
  String get dashNeverFetched => 'never fetched';

  @override
  String get dashUnreadable => 'Could not read this repository';

  @override
  String get dashOpMerge => 'merging';

  @override
  String get dashOpRebase => 'rebasing';

  @override
  String get dashOpAm => 'applying patches';

  @override
  String get dashOpCherryPick => 'cherry-picking';

  @override
  String get dashOpRevert => 'reverting';

  @override
  String get dashOpBisect => 'bisecting';

  @override
  String get dashRunQueued => 'queued';

  @override
  String get dashRunFetched => 'fetched';

  @override
  String get dashRunPulled => 'pulled';

  @override
  String get dashRunFailed => 'failed';

  @override
  String get dashRunCancelled => 'cancelled';

  @override
  String get dashSkipNoRemote => 'skipped: no remote';

  @override
  String get dashSkipUnreadable => 'skipped: could not read';

  @override
  String get dashSkipOperation => 'skipped: operation in progress';

  @override
  String get dashSkipDetached => 'skipped: detached HEAD';

  @override
  String get dashSkipNoUpstream => 'skipped: no upstream';

  @override
  String get dashSkipUpstreamGone => 'skipped: upstream gone';

  @override
  String get dashSkipDirty => 'skipped: uncommitted changes';

  @override
  String get dashSkipDiverged => 'skipped: diverged, needs a merge or rebase';

  @override
  String get dashSkipUpToDate => 'skipped: up to date';

  @override
  String get dashFetchBusy => 'Fetching all repositories';

  @override
  String get dashPullBusy => 'Pulling fast-forwardable repositories';

  @override
  String get dashFetchDone => 'Fetch all finished';

  @override
  String get dashPullDone => 'Pull finished';

  @override
  String dashBatchSummary(int done, int failed, int skipped, int cancelled) {
    return '$done done, $failed failed, $skipped skipped, $cancelled cancelled';
  }

  @override
  String get dashPaletteOpen => 'Open dashboard';

  @override
  String dashPaletteGoTo(String name) {
    return 'Go to $name';
  }

  @override
  String wtpSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get wtpStage => 'Stage';

  @override
  String get wtpUnstage => 'Unstage';

  @override
  String wtpStageSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Stage $count files',
      one: 'Stage $count file',
    );
    return '$_temp0';
  }

  @override
  String wtpUnstageSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unstage $count files',
      one: 'Unstage $count file',
    );
    return '$_temp0';
  }

  @override
  String wtpDiscardSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Discard $count files…',
      one: 'Discard $count file…',
    );
    return '$_temp0';
  }

  @override
  String wtpStashSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Stash $count files…',
      one: 'Stash $count file…',
    );
    return '$_temp0';
  }

  @override
  String get wtpClearSelection => 'Clear selection';

  @override
  String wtpDiscardSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Discard changes to $count files?',
      one: 'Discard changes to $count file?',
    );
    return '$_temp0';
  }

  @override
  String get wtpDiscardSelectedBody =>
      'Tracked files go back to their committed state, dropping staged and unstaged changes; untracked files are deleted. You can undo it.';
}
