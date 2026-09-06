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
  String get ropMessageOptional => 'Message (optional)';

  @override
  String get ropOnlyStaged => 'Only staged changes';

  @override
  String get ropStash => 'Stash';

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
  String get wtpAddCoauthor => '+ Co-author';

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
  String get diffCouldNotLoad => 'Could not load diff';

  @override
  String get diffBinaryFile => 'Binary file — diff not shown';

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
}
