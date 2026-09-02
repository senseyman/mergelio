import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Mergelio'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @tooltipTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal (⌘`)'**
  String get tooltipTerminal;

  /// No description provided for @tooltipSearch.
  ///
  /// In en, this message translates to:
  /// **'Search (⌘F)'**
  String get tooltipSearch;

  /// No description provided for @tooltipPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette (⌘K)'**
  String get tooltipPalette;

  /// No description provided for @tooltipPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences (⌘,)'**
  String get tooltipPreferences;

  /// No description provided for @tooltipProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get tooltipProfiles;

  /// No description provided for @tooltipProjectFiles.
  ///
  /// In en, this message translates to:
  /// **'Project files'**
  String get tooltipProjectFiles;

  /// No description provided for @tooltipHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get tooltipHistory;

  /// No description provided for @opFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get opFetch;

  /// No description provided for @opPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get opPull;

  /// No description provided for @opPullRebase.
  ///
  /// In en, this message translates to:
  /// **'Pull (rebase)'**
  String get opPullRebase;

  /// No description provided for @opPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get opPush;

  /// No description provided for @opPushOrigin.
  ///
  /// In en, this message translates to:
  /// **'Push origin'**
  String get opPushOrigin;

  /// No description provided for @opForcePush.
  ///
  /// In en, this message translates to:
  /// **'Force-push (with lease)'**
  String get opForcePush;

  /// No description provided for @opUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get opUndo;

  /// No description provided for @opRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get opRedo;

  /// No description provided for @welcomeOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get welcomeOpen;

  /// No description provided for @welcomeClone.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get welcomeClone;

  /// No description provided for @welcomeCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get welcomeCreate;

  /// No description provided for @welcomeRecents.
  ///
  /// In en, this message translates to:
  /// **'Recent repositories'**
  String get welcomeRecents;

  /// No description provided for @welcomeNoRecents.
  ///
  /// In en, this message translates to:
  /// **'No recent repositories yet'**
  String get welcomeNoRecents;

  /// No description provided for @prefsTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get prefsTitle;

  /// No description provided for @prefsTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get prefsTabGeneral;

  /// No description provided for @prefsTabAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get prefsTabAppearance;

  /// No description provided for @prefsTabShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get prefsTabShortcuts;

  /// No description provided for @prefsTabCredentials.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get prefsTabCredentials;

  /// No description provided for @prefsAutoFetch.
  ///
  /// In en, this message translates to:
  /// **'Auto-fetch'**
  String get prefsAutoFetch;

  /// No description provided for @prefsAutoFetchInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto-fetch interval'**
  String get prefsAutoFetchInterval;

  /// No description provided for @prefsConfirmDestructive.
  ///
  /// In en, this message translates to:
  /// **'Confirm destructive actions'**
  String get prefsConfirmDestructive;

  /// No description provided for @prefsRestoreTabs.
  ///
  /// In en, this message translates to:
  /// **'Restore tabs on launch'**
  String get prefsRestoreTabs;

  /// No description provided for @prefsTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous usage data'**
  String get prefsTelemetry;

  /// No description provided for @prefsZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get prefsZoom;

  /// No description provided for @prefsGroupStyle.
  ///
  /// In en, this message translates to:
  /// **'Group switcher'**
  String get prefsGroupStyle;

  /// No description provided for @prefsPullStrategy.
  ///
  /// In en, this message translates to:
  /// **'Pull strategy'**
  String get prefsPullStrategy;

  /// No description provided for @prefsDateFormat.
  ///
  /// In en, this message translates to:
  /// **'Date format'**
  String get prefsDateFormat;

  /// No description provided for @prefsGraphColumns.
  ///
  /// In en, this message translates to:
  /// **'Graph columns'**
  String get prefsGraphColumns;

  /// No description provided for @prefsCompactRows.
  ///
  /// In en, this message translates to:
  /// **'Compact rows'**
  String get prefsCompactRows;

  /// No description provided for @prefsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get prefsLanguage;

  /// No description provided for @prefsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get prefsTheme;

  /// No description provided for @prefsAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get prefsAccent;

  /// No description provided for @prefsBranchColours.
  ///
  /// In en, this message translates to:
  /// **'Branch colours'**
  String get prefsBranchColours;

  /// No description provided for @prefsResetColours.
  ///
  /// In en, this message translates to:
  /// **'Reset colours'**
  String get prefsResetColours;

  /// No description provided for @prefsSavedThemes.
  ///
  /// In en, this message translates to:
  /// **'Saved themes'**
  String get prefsSavedThemes;

  /// No description provided for @prefsSaveCurrent.
  ///
  /// In en, this message translates to:
  /// **'Save current…'**
  String get prefsSaveCurrent;

  /// No description provided for @strategyMerge.
  ///
  /// In en, this message translates to:
  /// **'merge'**
  String get strategyMerge;

  /// No description provided for @strategyRebase.
  ///
  /// In en, this message translates to:
  /// **'rebase'**
  String get strategyRebase;

  /// No description provided for @dateMedium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get dateMedium;

  /// No description provided for @dateIso.
  ///
  /// In en, this message translates to:
  /// **'ISO'**
  String get dateIso;

  /// No description provided for @dateShort.
  ///
  /// In en, this message translates to:
  /// **'short'**
  String get dateShort;

  /// No description provided for @prefsClockFormat.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get prefsClockFormat;

  /// No description provided for @clock24.
  ///
  /// In en, this message translates to:
  /// **'24-hour'**
  String get clock24;

  /// No description provided for @clock12.
  ///
  /// In en, this message translates to:
  /// **'12-hour'**
  String get clock12;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'system'**
  String get themeSystem;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Українська'**
  String get languageUkrainian;

  /// No description provided for @graphHistory.
  ///
  /// In en, this message translates to:
  /// **'HISTORY'**
  String get graphHistory;

  /// No description provided for @graphCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get graphCompact;

  /// No description provided for @filterHideMerges.
  ///
  /// In en, this message translates to:
  /// **'Hide merges'**
  String get filterHideMerges;

  /// No description provided for @filterHideTags.
  ///
  /// In en, this message translates to:
  /// **'Hide tags'**
  String get filterHideTags;

  /// No description provided for @filterContentRegex.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get filterContentRegex;

  /// No description provided for @searchContentHint.
  ///
  /// In en, this message translates to:
  /// **'In diffs…'**
  String get searchContentHint;

  /// No description provided for @searchContentHelp.
  ///
  /// In en, this message translates to:
  /// **'Commits that added or removed this text'**
  String get searchContentHelp;

  /// No description provided for @searchContentRegexHelp.
  ///
  /// In en, this message translates to:
  /// **'Commits with an added or removed line matching this regular expression'**
  String get searchContentRegexHelp;

  /// No description provided for @searchRunning.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searchRunning;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get searchNoMatches;

  /// No description provided for @menuCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout this commit'**
  String get menuCheckout;

  /// No description provided for @menuCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create branch here'**
  String get menuCreateBranch;

  /// No description provided for @menuCreateTag.
  ///
  /// In en, this message translates to:
  /// **'Create tag here'**
  String get menuCreateTag;

  /// No description provided for @menuCherryPick.
  ///
  /// In en, this message translates to:
  /// **'Cherry-pick'**
  String get menuCherryPick;

  /// No description provided for @menuRevert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get menuRevert;

  /// No description provided for @menuRebaseHere.
  ///
  /// In en, this message translates to:
  /// **'Rebase to here…'**
  String get menuRebaseHere;

  /// No description provided for @menuResetHard.
  ///
  /// In en, this message translates to:
  /// **'Reset here (--hard)'**
  String get menuResetHard;

  /// No description provided for @menuEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message…'**
  String get menuEditMessage;

  /// No description provided for @menuCopySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy summary'**
  String get menuCopySummary;

  /// No description provided for @menuCopyDescription.
  ///
  /// In en, this message translates to:
  /// **'Copy description'**
  String get menuCopyDescription;

  /// No description provided for @menuCopyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get menuCopyMessage;

  /// No description provided for @menuCopySha.
  ///
  /// In en, this message translates to:
  /// **'Copy SHA'**
  String get menuCopySha;

  /// No description provided for @rewordTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit commit message'**
  String get rewordTitle;

  /// No description provided for @rewordPushedTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewrite a pushed commit?'**
  String get rewordPushedTitle;

  /// No description provided for @rewordPushedBody.
  ///
  /// In en, this message translates to:
  /// **'This commit is already on {branches}. Changing its message rewrites history, so the branch will need a force push and anyone who pulled it will have to reset.'**
  String rewordPushedBody(String branches);

  /// No description provided for @rewordPushedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Rewrite anyway'**
  String get rewordPushedConfirm;

  /// No description provided for @mergeResolveConflicts.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflicts'**
  String get mergeResolveConflicts;

  /// No description provided for @mergeRebase.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get mergeRebase;

  /// No description provided for @mergeCherryPick.
  ///
  /// In en, this message translates to:
  /// **'Cherry-pick {sha}'**
  String mergeCherryPick(String sha);

  /// No description provided for @mergeRevert.
  ///
  /// In en, this message translates to:
  /// **'Revert {sha}'**
  String mergeRevert(String sha);

  /// No description provided for @mergeInto.
  ///
  /// In en, this message translates to:
  /// **'Merge {branch} → {into}'**
  String mergeInto(String branch, String into);

  /// No description provided for @mergeBranch.
  ///
  /// In en, this message translates to:
  /// **'Merge {branch}'**
  String mergeBranch(String branch);

  /// No description provided for @mergeResolvedCount.
  ///
  /// In en, this message translates to:
  /// **'{resolved} / {total} resolved'**
  String mergeResolvedCount(int resolved, int total);

  /// No description provided for @mergeNextUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Next unresolved'**
  String get mergeNextUnresolved;

  /// No description provided for @mergeAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get mergeAbort;

  /// No description provided for @mergeResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get mergeResolve;

  /// No description provided for @a11yCommitRow.
  ///
  /// In en, this message translates to:
  /// **'Commit {sha} by {author}: {message}'**
  String a11yCommitRow(String sha, String author, String message);

  /// No description provided for @a11yWorkingChanges.
  ///
  /// In en, this message translates to:
  /// **'Working tree changes'**
  String get a11yWorkingChanges;

  /// No description provided for @a11yCommitGraph.
  ///
  /// In en, this message translates to:
  /// **'Commit history graph'**
  String get a11yCommitGraph;

  /// No description provided for @shellAddRepository.
  ///
  /// In en, this message translates to:
  /// **'Add repository'**
  String get shellAddRepository;

  /// No description provided for @shellOpenRepoMenu.
  ///
  /// In en, this message translates to:
  /// **'Open…'**
  String get shellOpenRepoMenu;

  /// No description provided for @shellCloneRepoMenu.
  ///
  /// In en, this message translates to:
  /// **'Clone…'**
  String get shellCloneRepoMenu;

  /// No description provided for @shellCreateRepoMenu.
  ///
  /// In en, this message translates to:
  /// **'Create…'**
  String get shellCreateRepoMenu;

  /// No description provided for @shellRepoGroup.
  ///
  /// In en, this message translates to:
  /// **'Repo group'**
  String get shellRepoGroup;

  /// No description provided for @shellAllGroups.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get shellAllGroups;

  /// No description provided for @shellNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get shellNewGroup;

  /// No description provided for @shellNewGroupMenu.
  ///
  /// In en, this message translates to:
  /// **'New group…'**
  String get shellNewGroupMenu;

  /// No description provided for @shellGroupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get shellGroupName;

  /// No description provided for @shellRenameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get shellRenameGroup;

  /// No description provided for @shellRenameMenu.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get shellRenameMenu;

  /// No description provided for @shellRenameGroupMenu.
  ///
  /// In en, this message translates to:
  /// **'Rename group…'**
  String get shellRenameGroupMenu;

  /// No description provided for @shellDeleteGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete group?'**
  String get shellDeleteGroupTitle;

  /// No description provided for @shellDeleteGroupMenu.
  ///
  /// In en, this message translates to:
  /// **'Delete group…'**
  String get shellDeleteGroupMenu;

  /// No description provided for @shellDeleteGroupBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is removed from the switcher. Repositories in it stay open, without a group.'**
  String shellDeleteGroupBody(String name);

  /// No description provided for @shellCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get shellCloseTab;

  /// No description provided for @shellCloseOthers.
  ///
  /// In en, this message translates to:
  /// **'Close others'**
  String get shellCloseOthers;

  /// No description provided for @shellRemoveFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from {name}'**
  String shellRemoveFromGroup(String name);

  /// No description provided for @shellMoveToGroup.
  ///
  /// In en, this message translates to:
  /// **'Move to {name}'**
  String shellMoveToGroup(String name);

  /// No description provided for @tabWorktree.
  ///
  /// In en, this message translates to:
  /// **'Worktree'**
  String get tabWorktree;

  /// No description provided for @tabWorktreeOf.
  ///
  /// In en, this message translates to:
  /// **'Worktree of {parent}'**
  String tabWorktreeOf(String parent);

  /// No description provided for @wtAdd.
  ///
  /// In en, this message translates to:
  /// **'Add worktree'**
  String get wtAdd;

  /// No description provided for @wtLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get wtLocation;

  /// No description provided for @wtBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get wtBrowse;

  /// No description provided for @wtNewBranch.
  ///
  /// In en, this message translates to:
  /// **'New branch'**
  String get wtNewBranch;

  /// No description provided for @wtFrom.
  ///
  /// In en, this message translates to:
  /// **'from'**
  String get wtFrom;

  /// No description provided for @wtExistingBranch.
  ///
  /// In en, this message translates to:
  /// **'Existing branch'**
  String get wtExistingBranch;

  /// No description provided for @wtDetachedAt.
  ///
  /// In en, this message translates to:
  /// **'Detached at'**
  String get wtDetachedAt;

  /// No description provided for @wtHeldBy.
  ///
  /// In en, this message translates to:
  /// **'— in {name}'**
  String wtHeldBy(String name);

  /// No description provided for @wtBranchExists.
  ///
  /// In en, this message translates to:
  /// **'That branch already exists'**
  String get wtBranchExists;

  /// No description provided for @wtDirNotEmpty.
  ///
  /// In en, this message translates to:
  /// **'That directory is not empty'**
  String get wtDirNotEmpty;

  /// No description provided for @wtSubmodulesNote.
  ///
  /// In en, this message translates to:
  /// **'Submodules are not checked out in a new worktree; initialise them there yourself.'**
  String get wtSubmodulesNote;

  /// No description provided for @wtOpenInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in a new tab'**
  String get wtOpenInNewTab;

  /// No description provided for @wtRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove worktree?'**
  String get wtRemoveTitle;

  /// No description provided for @wtCheckedOutBranch.
  ///
  /// In en, this message translates to:
  /// **'Checked out: {branch}'**
  String wtCheckedOutBranch(String branch);

  /// No description provided for @wtDirDeleted.
  ///
  /// In en, this message translates to:
  /// **'The directory will be deleted.'**
  String get wtDirDeleted;

  /// No description provided for @wtRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get wtRemove;

  /// No description provided for @wtHasChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Worktree has changes'**
  String get wtHasChangesTitle;

  /// No description provided for @wtForcingDiscards.
  ///
  /// In en, this message translates to:
  /// **'Forcing discards those changes.'**
  String get wtForcingDiscards;

  /// No description provided for @wtForceRemove.
  ///
  /// In en, this message translates to:
  /// **'Force remove'**
  String get wtForceRemove;

  /// No description provided for @wtMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move worktree'**
  String get wtMoveTitle;

  /// No description provided for @wtAlreadyThere.
  ///
  /// In en, this message translates to:
  /// **'That is where it already is'**
  String get wtAlreadyThere;

  /// No description provided for @wtNewLocationFor.
  ///
  /// In en, this message translates to:
  /// **'New location for {name}'**
  String wtNewLocationFor(String name);

  /// No description provided for @wtMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get wtMove;

  /// No description provided for @wtAlreadyCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'Already checked out'**
  String get wtAlreadyCheckedOut;

  /// No description provided for @wtCheckedOutInWorktreeAt.
  ///
  /// In en, this message translates to:
  /// **'{branch} is checked out in the worktree at'**
  String wtCheckedOutInWorktreeAt(String branch);

  /// No description provided for @wtTwoPlacesWarning.
  ///
  /// In en, this message translates to:
  /// **'Checking out anyway puts the branch in two places at once; commits made in one leave the other behind.'**
  String get wtTwoPlacesWarning;

  /// No description provided for @wtCheckoutAnyway.
  ///
  /// In en, this message translates to:
  /// **'Checkout anyway'**
  String get wtCheckoutAnyway;

  /// No description provided for @wtOpenWorktree.
  ///
  /// In en, this message translates to:
  /// **'Open worktree'**
  String get wtOpenWorktree;

  /// No description provided for @wtPruneTitle.
  ///
  /// In en, this message translates to:
  /// **'Prune stale worktrees'**
  String get wtPruneTitle;

  /// No description provided for @wtNothingToPrune.
  ///
  /// In en, this message translates to:
  /// **'Nothing to prune.'**
  String get wtNothingToPrune;

  /// No description provided for @wtEntriesWillBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'These entries will be removed:'**
  String get wtEntriesWillBeRemoved;

  /// No description provided for @wtPrune.
  ///
  /// In en, this message translates to:
  /// **'Prune'**
  String get wtPrune;

  /// No description provided for @sbRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get sbRepository;

  /// No description provided for @sbCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get sbCollapse;

  /// No description provided for @sbCouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read repository'**
  String get sbCouldNotRead;

  /// No description provided for @sbRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get sbRetry;

  /// No description provided for @sbBranches.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get sbBranches;

  /// No description provided for @sbNoBranches.
  ///
  /// In en, this message translates to:
  /// **'No branches'**
  String get sbNoBranches;

  /// No description provided for @sbRemotes.
  ///
  /// In en, this message translates to:
  /// **'Remotes'**
  String get sbRemotes;

  /// No description provided for @sbNoRemotes.
  ///
  /// In en, this message translates to:
  /// **'No remotes'**
  String get sbNoRemotes;

  /// No description provided for @sbTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get sbTags;

  /// No description provided for @sbNoTags.
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get sbNoTags;

  /// No description provided for @sbStashes.
  ///
  /// In en, this message translates to:
  /// **'Stashes'**
  String get sbStashes;

  /// No description provided for @sbNoStashes.
  ///
  /// In en, this message translates to:
  /// **'No stashes'**
  String get sbNoStashes;

  /// No description provided for @sbSubmodules.
  ///
  /// In en, this message translates to:
  /// **'Submodules'**
  String get sbSubmodules;

  /// No description provided for @sbNoSubmodules.
  ///
  /// In en, this message translates to:
  /// **'No submodules'**
  String get sbNoSubmodules;

  /// No description provided for @sbAddRemoteRow.
  ///
  /// In en, this message translates to:
  /// **'Add remote…'**
  String get sbAddRemoteRow;

  /// No description provided for @sbAddRemoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Add remote'**
  String get sbAddRemoteTitle;

  /// No description provided for @sbAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get sbAdd;

  /// No description provided for @sbAddSubmoduleRow.
  ///
  /// In en, this message translates to:
  /// **'Add submodule…'**
  String get sbAddSubmoduleRow;

  /// No description provided for @sbPop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get sbPop;

  /// No description provided for @sbInit.
  ///
  /// In en, this message translates to:
  /// **'Init'**
  String get sbInit;

  /// No description provided for @sbUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get sbUpdate;

  /// No description provided for @sbUpdateToRemote.
  ///
  /// In en, this message translates to:
  /// **'Update to remote'**
  String get sbUpdateToRemote;

  /// No description provided for @sbSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sbSync;

  /// No description provided for @sbDeinit.
  ///
  /// In en, this message translates to:
  /// **'Deinit'**
  String get sbDeinit;

  /// No description provided for @sbReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get sbReset;

  /// No description provided for @sbResetToUpstreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset {branch} to {upstream}?'**
  String sbResetToUpstreamTitle(String branch, String upstream);

  /// No description provided for @sbResetUnpushedBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} unpushed commit on {branch} will be removed. This can be undone.} other{{count} unpushed commits on {branch} will be removed. This can be undone.}}'**
  String sbResetUnpushedBody(int count, String branch);

  /// No description provided for @sbResetMovedBody.
  ///
  /// In en, this message translates to:
  /// **'{branch} will be moved to {upstream}. This can be undone.'**
  String sbResetMovedBody(String branch, String upstream);

  /// No description provided for @sbCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get sbCheckout;

  /// No description provided for @sbMergeIntoCurrent.
  ///
  /// In en, this message translates to:
  /// **'Merge into current'**
  String get sbMergeIntoCurrent;

  /// No description provided for @sbRebaseOntoCurrent.
  ///
  /// In en, this message translates to:
  /// **'Rebase onto current'**
  String get sbRebaseOntoCurrent;

  /// No description provided for @sbSetUpstreamItem.
  ///
  /// In en, this message translates to:
  /// **'Set upstream…'**
  String get sbSetUpstreamItem;

  /// No description provided for @sbSetUpstreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Set upstream for {branch}'**
  String sbSetUpstreamTitle(String branch);

  /// No description provided for @sbSetUpstreamHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. origin/{branch}'**
  String sbSetUpstreamHint(String branch);

  /// No description provided for @sbResetToRemote.
  ///
  /// In en, this message translates to:
  /// **'Reset to remote…'**
  String get sbResetToRemote;

  /// No description provided for @sbRenameItem.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get sbRenameItem;

  /// No description provided for @sbRenameBranchTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename branch'**
  String get sbRenameBranchTitle;

  /// No description provided for @sbDeleteBranch.
  ///
  /// In en, this message translates to:
  /// **'Delete branch'**
  String get sbDeleteBranch;

  /// No description provided for @sbDeleteBranchTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {branch}?'**
  String sbDeleteBranchTitle(String branch);

  /// No description provided for @sbDeleteBranchBody.
  ///
  /// In en, this message translates to:
  /// **'The branch ref will be removed. This can be undone.'**
  String get sbDeleteBranchBody;

  /// No description provided for @sbDeleteBranchAndRemote.
  ///
  /// In en, this message translates to:
  /// **'Delete branch and remote…'**
  String get sbDeleteBranchAndRemote;

  /// No description provided for @sbDeleteBothTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {branch} and {upstream}?'**
  String sbDeleteBothTitle(String branch, String upstream);

  /// No description provided for @sbDeleteBothBody.
  ///
  /// In en, this message translates to:
  /// **'The branch will be removed here and on the remote. Only the local half can be undone.'**
  String get sbDeleteBothBody;

  /// No description provided for @sbDeleteBoth.
  ///
  /// In en, this message translates to:
  /// **'Delete both'**
  String get sbDeleteBoth;

  /// No description provided for @sbCheckedOutIn.
  ///
  /// In en, this message translates to:
  /// **'Checked out in {name}'**
  String sbCheckedOutIn(String name);

  /// No description provided for @sbMergeSourceInto.
  ///
  /// In en, this message translates to:
  /// **'Merge «{source}» into «{target}»'**
  String sbMergeSourceInto(String source, String target);

  /// No description provided for @sbRebaseSourceOnto.
  ///
  /// In en, this message translates to:
  /// **'Rebase «{source}» onto «{target}»'**
  String sbRebaseSourceOnto(String source, String target);

  /// No description provided for @sbTipSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'Click to show its tip · double-click to switch to {branch}'**
  String sbTipSwitchHint(String branch);

  /// No description provided for @sbTipCheckoutHint.
  ///
  /// In en, this message translates to:
  /// **'Click to show its tip · double-click to check out {name}'**
  String sbTipCheckoutHint(String name);

  /// No description provided for @sbHasLocalBranch.
  ///
  /// In en, this message translates to:
  /// **'Has a local branch'**
  String get sbHasLocalBranch;

  /// No description provided for @sbSwitchTo.
  ///
  /// In en, this message translates to:
  /// **'Switch to {branch}'**
  String sbSwitchTo(String branch);

  /// No description provided for @sbCheckOutNamed.
  ///
  /// In en, this message translates to:
  /// **'Check out {name}'**
  String sbCheckOutNamed(String name);

  /// No description provided for @sbMergeNamedIntoCurrent.
  ///
  /// In en, this message translates to:
  /// **'Merge {name} into current'**
  String sbMergeNamedIntoCurrent(String name);

  /// No description provided for @sbResetToThis.
  ///
  /// In en, this message translates to:
  /// **'Reset {branch} to this'**
  String sbResetToThis(String branch);

  /// No description provided for @sbDeleteRemoteBranchTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String sbDeleteRemoteBranchTitle(String name);

  /// No description provided for @sbDeleteRemoteBranchBody.
  ///
  /// In en, this message translates to:
  /// **'The branch will be deleted on {remote}. Any local branch of the same name stays. This cannot be undone.'**
  String sbDeleteRemoteBranchBody(String remote);

  /// No description provided for @sbDeleteNamedItem.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}…'**
  String sbDeleteNamedItem(String name);

  /// No description provided for @sbFetchRemote.
  ///
  /// In en, this message translates to:
  /// **'Fetch {remote}'**
  String sbFetchRemote(String remote);

  /// No description provided for @sbPrune.
  ///
  /// In en, this message translates to:
  /// **'Prune'**
  String get sbPrune;

  /// No description provided for @sbCopyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get sbCopyUrl;

  /// No description provided for @sbEditRemoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit remote'**
  String get sbEditRemoteTitle;

  /// No description provided for @sbEditRemoteItem.
  ///
  /// In en, this message translates to:
  /// **'Edit remote…'**
  String get sbEditRemoteItem;

  /// No description provided for @sbRemoveRemoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove remote {remote}?'**
  String sbRemoveRemoteTitle(String remote);

  /// No description provided for @sbRemoveRemoteBody.
  ///
  /// In en, this message translates to:
  /// **'Its remote-tracking branches go with it. Undo restores the remote; fetch to bring the branches back.'**
  String get sbRemoveRemoteBody;

  /// No description provided for @sbRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get sbRemove;

  /// No description provided for @sbRemoveRemoteItem.
  ///
  /// In en, this message translates to:
  /// **'Remove remote…'**
  String get sbRemoveRemoteItem;

  /// No description provided for @sbPushTag.
  ///
  /// In en, this message translates to:
  /// **'Push tag'**
  String get sbPushTag;

  /// No description provided for @sbCopyName.
  ///
  /// In en, this message translates to:
  /// **'Copy name'**
  String get sbCopyName;

  /// No description provided for @sbDeleteTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete tag {tag}?'**
  String sbDeleteTagTitle(String tag);

  /// No description provided for @sbDeleteTagBody.
  ///
  /// In en, this message translates to:
  /// **'The tag will be removed locally. This can be undone.'**
  String get sbDeleteTagBody;

  /// No description provided for @sbDeleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get sbDeleteTag;

  /// No description provided for @sbDropStashTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop {ref}?'**
  String sbDropStashTitle(String ref);

  /// No description provided for @sbDropStashBody.
  ///
  /// In en, this message translates to:
  /// **'The stash will be deleted. An Undo toast lets you restore it.'**
  String get sbDropStashBody;

  /// No description provided for @sbDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get sbDrop;

  /// No description provided for @sbRemoveSubmoduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String sbRemoveSubmoduleTitle(String name);

  /// No description provided for @sbRemoveSubmoduleBody.
  ///
  /// In en, this message translates to:
  /// **'The submodule at {path} will be deinitialized and removed from .gitmodules. This cannot be undone.'**
  String sbRemoveSubmoduleBody(String path);

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @commonUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get commonUnsavedChanges;

  /// No description provided for @commonFileChangedOnDisk.
  ///
  /// In en, this message translates to:
  /// **'File changed on disk'**
  String get commonFileChangedOnDisk;

  /// No description provided for @commonOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get commonOverwrite;

  /// No description provided for @diffDiscardEditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard edits?'**
  String get diffDiscardEditsTitle;

  /// No description provided for @diffDiscardEditsBody.
  ///
  /// In en, this message translates to:
  /// **'What you typed here has not been written to {path}.'**
  String diffDiscardEditsBody(String path);

  /// No description provided for @diffSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get diffSelectAll;

  /// No description provided for @diffDiscardFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard {path}?'**
  String diffDiscardFileTitle(String path);

  /// No description provided for @diffDiscardFileBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the untracked file. You can undo it.'**
  String get diffDiscardFileBody;

  /// No description provided for @filesEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get filesEditor;

  /// No description provided for @filesClosePath.
  ///
  /// In en, this message translates to:
  /// **'Close {path}'**
  String filesClosePath(String path);

  /// No description provided for @filesName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get filesName;

  /// No description provided for @filesRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get filesRenameTitle;

  /// No description provided for @filesNewName.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get filesNewName;

  /// No description provided for @filesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String filesDeleteTitle(String name);

  /// No description provided for @filesDiscardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes to {name}?'**
  String filesDiscardChangesTitle(String name);

  /// No description provided for @filesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get filesRefresh;

  /// No description provided for @filesCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get filesCollapse;

  /// No description provided for @wtpAlsoDeleteUntracked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Also delete {count} untracked file} other{Also delete {count} untracked files}}'**
  String wtpAlsoDeleteUntracked(int count);

  /// No description provided for @diffDiscardHunkTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard hunk?'**
  String get diffDiscardHunkTitle;

  /// No description provided for @diffDiscardLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Discard {count} line?} other{Discard {count} lines?}}'**
  String diffDiscardLinesTitle(int count);

  /// No description provided for @diffDiscardLinesBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the selected changes from the working tree. You can undo it.'**
  String get diffDiscardLinesBody;

  /// No description provided for @bbOpenRepoFirst.
  ///
  /// In en, this message translates to:
  /// **'Open a repository first'**
  String get bbOpenRepoFirst;

  /// No description provided for @bbOperationRunning.
  ///
  /// In en, this message translates to:
  /// **'An operation is already running'**
  String get bbOperationRunning;

  /// No description provided for @bbNoRemote.
  ///
  /// In en, this message translates to:
  /// **'No remote configured'**
  String get bbNoRemote;

  /// No description provided for @bbUndoLabelled.
  ///
  /// In en, this message translates to:
  /// **'Undo {label} (⌘Z)'**
  String bbUndoLabelled(String label);

  /// No description provided for @bbUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo (⌘Z)'**
  String get bbUndo;

  /// No description provided for @bbRedoLabelled.
  ///
  /// In en, this message translates to:
  /// **'Redo {label} (⌘⇧Z)'**
  String bbRedoLabelled(String label);

  /// No description provided for @bbRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo (⌘⇧Z)'**
  String get bbRedo;

  /// No description provided for @bbFetchOrigin.
  ///
  /// In en, this message translates to:
  /// **'Fetch origin'**
  String get bbFetchOrigin;

  /// No description provided for @bbFetchAllRemotes.
  ///
  /// In en, this message translates to:
  /// **'Fetch all remotes'**
  String get bbFetchAllRemotes;

  /// No description provided for @bbPullAllRemotes.
  ///
  /// In en, this message translates to:
  /// **'Pull (all remotes)'**
  String get bbPullAllRemotes;

  /// No description provided for @bbForcePushTitle.
  ///
  /// In en, this message translates to:
  /// **'Force-push?'**
  String get bbForcePushTitle;

  /// No description provided for @bbForcePushBody.
  ///
  /// In en, this message translates to:
  /// **'This overwrites the remote branch with your local history (using --force-with-lease, which still refuses if the remote moved unexpectedly).'**
  String get bbForcePushBody;

  /// No description provided for @bbForcePush.
  ///
  /// In en, this message translates to:
  /// **'Force-push'**
  String get bbForcePush;

  /// No description provided for @bbBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get bbBranch;

  /// No description provided for @bbMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get bbMerge;

  /// No description provided for @bbStash.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get bbStash;

  /// No description provided for @sbarNoProfile.
  ///
  /// In en, this message translates to:
  /// **'No profile'**
  String get sbarNoProfile;

  /// No description provided for @sbarNoRepository.
  ///
  /// In en, this message translates to:
  /// **'No repository'**
  String get sbarNoRepository;

  /// No description provided for @sbarDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get sbarDark;

  /// No description provided for @sbarLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get sbarLight;

  /// No description provided for @sbarCancelBusy.
  ///
  /// In en, this message translates to:
  /// **'Cancel {label}'**
  String sbarCancelBusy(String label);

  /// No description provided for @tbComingLater.
  ///
  /// In en, this message translates to:
  /// **'Coming in a later stage'**
  String get tbComingLater;

  /// No description provided for @tbTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get tbTerminal;

  /// No description provided for @tbGlobalSearch.
  ///
  /// In en, this message translates to:
  /// **'Global search'**
  String get tbGlobalSearch;

  /// No description provided for @tbCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get tbCommandPalette;

  /// No description provided for @railExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get railExpand;

  /// No description provided for @gaCheckoutBranch.
  ///
  /// In en, this message translates to:
  /// **'Checkout: {name}'**
  String gaCheckoutBranch(String name);

  /// No description provided for @gaFlyToCommit.
  ///
  /// In en, this message translates to:
  /// **'Fly to: {sha}  {message}'**
  String gaFlyToCommit(String sha, String message);

  /// No description provided for @rmcMomentsAgo.
  ///
  /// In en, this message translates to:
  /// **'moments ago'**
  String get rmcMomentsAgo;

  /// No description provided for @rmcMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String rmcMinutesAgo(int minutes);

  /// No description provided for @rmcHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String rmcHoursAgo(int hours);

  /// No description provided for @rmcDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String rmcDaysAgo(int days);

  /// No description provided for @rmcNotFetched.
  ///
  /// In en, this message translates to:
  /// **'This repository has not fetched yet.'**
  String get rmcNotFetched;

  /// No description provided for @rmcLastFetched.
  ///
  /// In en, this message translates to:
  /// **'Last fetched {age}.'**
  String rmcLastFetched(String age);

  /// No description provided for @rmcMergeFrom.
  ///
  /// In en, this message translates to:
  /// **'Merge from {remote}?'**
  String rmcMergeFrom(String remote);

  /// No description provided for @rmcStaleWarning.
  ///
  /// In en, this message translates to:
  /// **'{source} is a remote-tracking branch. It is only as current as the last fetch from {remote}.'**
  String rmcStaleWarning(String source, String remote);

  /// No description provided for @rmcMergeAsIs.
  ///
  /// In en, this message translates to:
  /// **'Merge as-is'**
  String get rmcMergeAsIs;

  /// No description provided for @rmcFetchAndMerge.
  ///
  /// In en, this message translates to:
  /// **'Fetch and merge'**
  String get rmcFetchAndMerge;

  /// No description provided for @ropCreateBranchTitle.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get ropCreateBranchTitle;

  /// No description provided for @ropCurrentBranch.
  ///
  /// In en, this message translates to:
  /// **'current branch'**
  String get ropCurrentBranch;

  /// No description provided for @ropMergeIntoTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge into {branch}'**
  String ropMergeIntoTitle(String branch);

  /// No description provided for @ropCreateTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Create tag'**
  String get ropCreateTagTitle;

  /// No description provided for @ropTagName.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get ropTagName;

  /// No description provided for @ropType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ropType;

  /// No description provided for @ropTagMessage.
  ///
  /// In en, this message translates to:
  /// **'Tag message'**
  String get ropTagMessage;

  /// No description provided for @ropStashChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Stash changes'**
  String get ropStashChangesTitle;

  /// No description provided for @ropBranchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get ropBranchName;

  /// No description provided for @ropStartFrom.
  ///
  /// In en, this message translates to:
  /// **'Start from'**
  String get ropStartFrom;

  /// No description provided for @ropCheckoutAfterCreating.
  ///
  /// In en, this message translates to:
  /// **'Check out after creating'**
  String get ropCheckoutAfterCreating;

  /// No description provided for @ropNoOtherBranches.
  ///
  /// In en, this message translates to:
  /// **'No other branches to merge.'**
  String get ropNoOtherBranches;

  /// No description provided for @ropBranchToMerge.
  ///
  /// In en, this message translates to:
  /// **'Branch to merge'**
  String get ropBranchToMerge;

  /// No description provided for @ropMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get ropMerge;

  /// No description provided for @ropMessageOptional.
  ///
  /// In en, this message translates to:
  /// **'Message (optional)'**
  String get ropMessageOptional;

  /// No description provided for @ropOnlyStaged.
  ///
  /// In en, this message translates to:
  /// **'Only staged changes'**
  String get ropOnlyStaged;

  /// No description provided for @ropStash.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get ropStash;

  /// No description provided for @shellPrevOpUnfinished.
  ///
  /// In en, this message translates to:
  /// **'A previous operation may not have finished'**
  String get shellPrevOpUnfinished;

  /// No description provided for @wtpChanges.
  ///
  /// In en, this message translates to:
  /// **'CHANGES'**
  String get wtpChanges;

  /// No description provided for @wtpDiscardAll.
  ///
  /// In en, this message translates to:
  /// **'Discard all changes'**
  String get wtpDiscardAll;

  /// No description provided for @wtpUnstaged.
  ///
  /// In en, this message translates to:
  /// **'UNSTAGED'**
  String get wtpUnstaged;

  /// No description provided for @wtpStageAll.
  ///
  /// In en, this message translates to:
  /// **'Stage all'**
  String get wtpStageAll;

  /// No description provided for @wtpStaged.
  ///
  /// In en, this message translates to:
  /// **'STAGED'**
  String get wtpStaged;

  /// No description provided for @wtpUnstageAll.
  ///
  /// In en, this message translates to:
  /// **'Unstage all'**
  String get wtpUnstageAll;

  /// No description provided for @wtpAbortTitle.
  ///
  /// In en, this message translates to:
  /// **'Abort {name}?'**
  String wtpAbortTitle(String name);

  /// No description provided for @wtpAbortBody.
  ///
  /// In en, this message translates to:
  /// **'The staged resolution is discarded and the repository goes back to where the {name} started.'**
  String wtpAbortBody(String name);

  /// No description provided for @wtpAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get wtpAbort;

  /// No description provided for @wtpOpPausedBody.
  ///
  /// In en, this message translates to:
  /// **'A {name} is paused. Review the staged files, then continue it.'**
  String wtpOpPausedBody(String name);

  /// No description provided for @wtpMergeOpenBody.
  ///
  /// In en, this message translates to:
  /// **'A merge is open. Review the staged files, then commit it.'**
  String get wtpMergeOpenBody;

  /// No description provided for @wtpContinueOp.
  ///
  /// In en, this message translates to:
  /// **'Continue {name}'**
  String wtpContinueOp(String name);

  /// No description provided for @wtpTreeClean.
  ///
  /// In en, this message translates to:
  /// **'Working tree clean'**
  String get wtpTreeClean;

  /// No description provided for @wtpNothingToCommit.
  ///
  /// In en, this message translates to:
  /// **'Nothing to commit'**
  String get wtpNothingToCommit;

  /// No description provided for @wtpSectionCount.
  ///
  /// In en, this message translates to:
  /// **'{label} ({count})'**
  String wtpSectionCount(String label, int count);

  /// No description provided for @wtpFileHistory.
  ///
  /// In en, this message translates to:
  /// **'File history'**
  String get wtpFileHistory;

  /// No description provided for @wtpBlame.
  ///
  /// In en, this message translates to:
  /// **'Blame'**
  String get wtpBlame;

  /// No description provided for @wtpDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get wtpDiscardChanges;

  /// No description provided for @wtpFinishOpFirst.
  ///
  /// In en, this message translates to:
  /// **'Finish the operation first'**
  String get wtpFinishOpFirst;

  /// No description provided for @wtpFinishOpBody.
  ///
  /// In en, this message translates to:
  /// **'Continue or abort it above; committing here would strand the rest of the sequence.'**
  String get wtpFinishOpBody;

  /// No description provided for @wtpMessageEmpty.
  ///
  /// In en, this message translates to:
  /// **'Commit message is empty'**
  String get wtpMessageEmpty;

  /// No description provided for @wtpNothingStaged.
  ///
  /// In en, this message translates to:
  /// **'Nothing staged to commit'**
  String get wtpNothingStaged;

  /// No description provided for @wtpCommitted.
  ///
  /// In en, this message translates to:
  /// **'Committed'**
  String get wtpCommitted;

  /// No description provided for @wtpCommitFailed.
  ///
  /// In en, this message translates to:
  /// **'Commit failed'**
  String get wtpCommitFailed;

  /// No description provided for @wtpSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get wtpSummary;

  /// No description provided for @wtpDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get wtpDescription;

  /// No description provided for @wtpCoauthorsHint.
  ///
  /// In en, this message translates to:
  /// **'Co-authors: Name <email>, Name2 <email2>'**
  String get wtpCoauthorsHint;

  /// No description provided for @wtpAmend.
  ///
  /// In en, this message translates to:
  /// **'Amend'**
  String get wtpAmend;

  /// No description provided for @wtpSign.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get wtpSign;

  /// No description provided for @wtpAddCoauthor.
  ///
  /// In en, this message translates to:
  /// **'+ Co-author'**
  String get wtpAddCoauthor;

  /// No description provided for @wtpCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get wtpCommit;

  /// No description provided for @wtpDiscardAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard all changes?'**
  String get wtpDiscardAllTitle;

  /// No description provided for @wtpDiscardAllBody.
  ///
  /// In en, this message translates to:
  /// **'This reverts every tracked file to its committed state, dropping staged and unstaged changes. You can undo it.'**
  String get wtpDiscardAllBody;

  /// No description provided for @wtpDiscardFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes to {path}?'**
  String wtpDiscardFileTitle(String path);

  /// No description provided for @wtpDiscardFileBody.
  ///
  /// In en, this message translates to:
  /// **'This reverts the file to its committed state, dropping staged and unstaged changes. You can undo it.'**
  String get wtpDiscardFileBody;

  /// No description provided for @wtsWorktrees.
  ///
  /// In en, this message translates to:
  /// **'Worktrees'**
  String get wtsWorktrees;

  /// No description provided for @wtsNoWorktrees.
  ///
  /// In en, this message translates to:
  /// **'No worktrees'**
  String get wtsNoWorktrees;

  /// No description provided for @wtsPruneMenu.
  ///
  /// In en, this message translates to:
  /// **'Prune stale worktrees…'**
  String get wtsPruneMenu;

  /// No description provided for @wtsLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock {name}'**
  String wtsLockTitle(String name);

  /// No description provided for @wtsReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get wtsReasonOptional;

  /// No description provided for @wtsLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get wtsLock;

  /// No description provided for @wtsLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get wtsLocked;

  /// No description provided for @wtsPrunable.
  ///
  /// In en, this message translates to:
  /// **'Prunable'**
  String get wtsPrunable;

  /// No description provided for @wtsOpenInTab.
  ///
  /// In en, this message translates to:
  /// **'Open in tab'**
  String get wtsOpenInTab;

  /// No description provided for @wtsRevealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get wtsRevealInFinder;

  /// No description provided for @wtsMoveMenu.
  ///
  /// In en, this message translates to:
  /// **'Move…'**
  String get wtsMoveMenu;

  /// No description provided for @wtsUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get wtsUnlock;

  /// No description provided for @wtsLockMenu.
  ///
  /// In en, this message translates to:
  /// **'Lock…'**
  String get wtsLockMenu;

  /// No description provided for @wtsRemoveMenu.
  ///
  /// In en, this message translates to:
  /// **'Remove…'**
  String get wtsRemoveMenu;

  /// No description provided for @cdCommit.
  ///
  /// In en, this message translates to:
  /// **'COMMIT'**
  String get cdCommit;

  /// No description provided for @cdWip.
  ///
  /// In en, this message translates to:
  /// **'‹ WIP'**
  String get cdWip;

  /// No description provided for @cdAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get cdAuthor;

  /// No description provided for @cdDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get cdDate;

  /// No description provided for @cdParent.
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get cdParent;

  /// No description provided for @cdCoauthored.
  ///
  /// In en, this message translates to:
  /// **'Co-authored'**
  String get cdCoauthored;

  /// No description provided for @cdChangedFiles.
  ///
  /// In en, this message translates to:
  /// **'CHANGED FILES'**
  String get cdChangedFiles;

  /// No description provided for @cdCouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read changes'**
  String get cdCouldNotRead;

  /// No description provided for @cdNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get cdNoChanges;

  /// No description provided for @cdSha.
  ///
  /// In en, this message translates to:
  /// **'SHA'**
  String get cdSha;

  /// No description provided for @asdTitle.
  ///
  /// In en, this message translates to:
  /// **'Add submodule'**
  String get asdTitle;

  /// No description provided for @asdRepoUrl.
  ///
  /// In en, this message translates to:
  /// **'Repository URL'**
  String get asdRepoUrl;

  /// No description provided for @asdPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get asdPath;

  /// No description provided for @asdPathHint.
  ///
  /// In en, this message translates to:
  /// **'folder in this repo'**
  String get asdPathHint;

  /// No description provided for @asdBranchOptional.
  ///
  /// In en, this message translates to:
  /// **'Branch (optional)'**
  String get asdBranchOptional;

  /// No description provided for @asdBranchHint.
  ///
  /// In en, this message translates to:
  /// **'track a branch'**
  String get asdBranchHint;

  /// No description provided for @rdName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get rdName;

  /// No description provided for @rdUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get rdUrl;

  /// No description provided for @bsResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset {branch} to {target}?'**
  String bsResetTitle(String branch, String target);

  /// No description provided for @bsResetBody.
  ///
  /// In en, this message translates to:
  /// **'This moves local {branch} to {target}, discarding any commits not on the remote. Uncommitted changes are stashed (undoable).'**
  String bsResetBody(String branch, String target);

  /// No description provided for @bsResetAndSwitch.
  ///
  /// In en, this message translates to:
  /// **'Reset & switch'**
  String get bsResetAndSwitch;

  /// No description provided for @wvChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get wvChanges;

  /// No description provided for @wvChangesSub.
  ///
  /// In en, this message translates to:
  /// **'Working tree · staging · commit'**
  String get wvChangesSub;

  /// No description provided for @rdlgCloneTitle.
  ///
  /// In en, this message translates to:
  /// **'Clone repository'**
  String get rdlgCloneTitle;

  /// No description provided for @rdlgCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create repository'**
  String get rdlgCreateTitle;

  /// No description provided for @rdlgFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get rdlgFolderName;

  /// No description provided for @rdlgFolderHint.
  ///
  /// In en, this message translates to:
  /// **'derived from the URL'**
  String get rdlgFolderHint;

  /// No description provided for @rdlgDestFolder.
  ///
  /// In en, this message translates to:
  /// **'Destination folder'**
  String get rdlgDestFolder;

  /// No description provided for @rdlgCloning.
  ///
  /// In en, this message translates to:
  /// **'Cloning…'**
  String get rdlgCloning;

  /// No description provided for @rdlgClone.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get rdlgClone;

  /// No description provided for @rdlgRepoName.
  ///
  /// In en, this message translates to:
  /// **'Repository name'**
  String get rdlgRepoName;

  /// No description provided for @rdlgParentFolder.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get rdlgParentFolder;

  /// No description provided for @rdlgDefaultBranch.
  ///
  /// In en, this message translates to:
  /// **'Default branch'**
  String get rdlgDefaultBranch;

  /// No description provided for @rdlgInitReadme.
  ///
  /// In en, this message translates to:
  /// **'Initialise with README.md'**
  String get rdlgInitReadme;

  /// No description provided for @rdlgAddGitignore.
  ///
  /// In en, this message translates to:
  /// **'Add an empty .gitignore'**
  String get rdlgAddGitignore;

  /// No description provided for @rdlgCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get rdlgCreating;

  /// No description provided for @rdlgChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder…'**
  String get rdlgChooseFolder;

  /// No description provided for @rdlgBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get rdlgBrowse;

  /// No description provided for @welTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Mergelio'**
  String get welTitle;

  /// No description provided for @welSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Free visual Git client. Get started:'**
  String get welSubtitle;

  /// No description provided for @welCloneSub.
  ///
  /// In en, this message translates to:
  /// **'From a URL (HTTPS/SSH) into a folder'**
  String get welCloneSub;

  /// No description provided for @welCreateSub.
  ///
  /// In en, this message translates to:
  /// **'New local repository with README/.gitignore'**
  String get welCreateSub;

  /// No description provided for @welOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open repository'**
  String get welOpenTitle;

  /// No description provided for @welOpenSub.
  ///
  /// In en, this message translates to:
  /// **'Choose an existing folder with .git'**
  String get welOpenSub;

  /// No description provided for @welUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get welUnpin;

  /// No description provided for @welPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get welPin;

  /// No description provided for @welRemoveRecent.
  ///
  /// In en, this message translates to:
  /// **'Remove from recents'**
  String get welRemoveRecent;

  /// No description provided for @welNotARepo.
  ///
  /// In en, this message translates to:
  /// **'Not a git repository'**
  String get welNotARepo;

  /// No description provided for @gvSearchCommits.
  ///
  /// In en, this message translates to:
  /// **'Search commits…'**
  String get gvSearchCommits;

  /// No description provided for @gvAuthorFilter.
  ///
  /// In en, this message translates to:
  /// **'Author…'**
  String get gvAuthorFilter;

  /// No description provided for @gvPrevMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous (⇧N)'**
  String get gvPrevMatch;

  /// No description provided for @gvNextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next (N)'**
  String get gvNextMatch;

  /// No description provided for @gvCloseSearch.
  ///
  /// In en, this message translates to:
  /// **'Close (Esc)'**
  String get gvCloseSearch;

  /// No description provided for @gvColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get gvColumns;

  /// No description provided for @gvUncommittedFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Uncommitted changes · {count} file} other{Uncommitted changes · {count} files}}'**
  String gvUncommittedFiles(int count);

  /// No description provided for @gvCannotRebaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot rebase onto this commit'**
  String get gvCannotRebaseTitle;

  /// No description provided for @gvCannotRebaseBody.
  ///
  /// In en, this message translates to:
  /// **'The commits above {sha} include a merge, which a rebase would flatten.'**
  String gvCannotRebaseBody(String sha);

  /// No description provided for @gvNothingToRebaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to rebase'**
  String get gvNothingToRebaseTitle;

  /// No description provided for @gvNothingToRebaseBody.
  ///
  /// In en, this message translates to:
  /// **'{sha} is already part of this branch and the plan changes nothing.'**
  String gvNothingToRebaseBody(String sha);

  /// No description provided for @gvResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset to {sha}?'**
  String gvResetTitle(String sha);

  /// No description provided for @gvResetBody.
  ///
  /// In en, this message translates to:
  /// **'Moves the current branch to this commit and discards all uncommitted changes. This cannot be undone from disk.'**
  String get gvResetBody;

  /// No description provided for @gvResetHard.
  ///
  /// In en, this message translates to:
  /// **'Reset --hard'**
  String get gvResetHard;

  /// No description provided for @ccBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get ccBranch;

  /// No description provided for @cpTypeCommand.
  ///
  /// In en, this message translates to:
  /// **'Type a command…'**
  String get cpTypeCommand;

  /// No description provided for @termClose.
  ///
  /// In en, this message translates to:
  /// **'Close terminal (⌘`)'**
  String get termClose;

  /// No description provided for @fiHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get fiHistory;

  /// No description provided for @fiCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load history'**
  String get fiCouldNotLoad;

  /// No description provided for @fiCouldNotBlame.
  ///
  /// In en, this message translates to:
  /// **'Could not blame this file'**
  String get fiCouldNotBlame;

  /// No description provided for @ftvFlatList.
  ///
  /// In en, this message translates to:
  /// **'Show as flat list'**
  String get ftvFlatList;

  /// No description provided for @ftvGroupByFolder.
  ///
  /// In en, this message translates to:
  /// **'Group by folder'**
  String get ftvGroupByFolder;

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmAction;

  /// No description provided for @pfScCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get pfScCommandPalette;

  /// No description provided for @pfScSearchCommits.
  ///
  /// In en, this message translates to:
  /// **'Search commits'**
  String get pfScSearchCommits;

  /// No description provided for @pfScNextPrevMatch.
  ///
  /// In en, this message translates to:
  /// **'Next / previous search match'**
  String get pfScNextPrevMatch;

  /// No description provided for @pfScCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit (in composer)'**
  String get pfScCommit;

  /// No description provided for @pfScCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get pfScCreateBranch;

  /// No description provided for @pfScCollapsePanel.
  ///
  /// In en, this message translates to:
  /// **'Collapse left panel'**
  String get pfScCollapsePanel;

  /// No description provided for @pfScToggleTerminal.
  ///
  /// In en, this message translates to:
  /// **'Toggle terminal'**
  String get pfScToggleTerminal;

  /// No description provided for @pfScZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom in / out'**
  String get pfScZoom;

  /// No description provided for @pfScResetZoom.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get pfScResetZoom;

  /// No description provided for @pfScUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo last action'**
  String get pfScUndo;

  /// No description provided for @pfScRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get pfScRedo;

  /// No description provided for @pfScPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get pfScPreferences;

  /// No description provided for @pfScCloseDialog.
  ///
  /// In en, this message translates to:
  /// **'Close dialog / cancel'**
  String get pfScCloseDialog;

  /// No description provided for @pfGenerateSshKey.
  ///
  /// In en, this message translates to:
  /// **'Generate SSH key'**
  String get pfGenerateSshKey;

  /// No description provided for @pfAddPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Run ssh-keygen -p -f ~/.ssh/{name} to add one.'**
  String pfAddPassphraseHint(String name);

  /// No description provided for @pfGenerateFailed.
  ///
  /// In en, this message translates to:
  /// **'Generate failed'**
  String get pfGenerateFailed;

  /// No description provided for @pfAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get pfAuthentication;

  /// No description provided for @pfAuthBody.
  ///
  /// In en, this message translates to:
  /// **'HTTPS remotes use your system git credential helper; SSH remotes use your SSH agent and keys. Mergelio never stores or reads your passwords or private keys — only public keys are listed here.'**
  String get pfAuthBody;

  /// No description provided for @pfSshKeys.
  ///
  /// In en, this message translates to:
  /// **'SSH KEYS'**
  String get pfSshKeys;

  /// No description provided for @pfGenerateKeyMenu.
  ///
  /// In en, this message translates to:
  /// **'Generate key…'**
  String get pfGenerateKeyMenu;

  /// No description provided for @pfNoSshKeys.
  ///
  /// In en, this message translates to:
  /// **'No SSH keys found in ~/.ssh'**
  String get pfNoSshKeys;

  /// No description provided for @pfCopyPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Copy public key'**
  String get pfCopyPublicKey;

  /// No description provided for @pfPublicKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Public key copied'**
  String get pfPublicKeyCopied;

  /// No description provided for @pfThemeJsonCopied.
  ///
  /// In en, this message translates to:
  /// **'Theme JSON copied'**
  String get pfThemeJsonCopied;

  /// No description provided for @pfImportTheme.
  ///
  /// In en, this message translates to:
  /// **'Import theme'**
  String get pfImportTheme;

  /// No description provided for @pfPasteThemeJson.
  ///
  /// In en, this message translates to:
  /// **'Paste theme JSON'**
  String get pfPasteThemeJson;

  /// No description provided for @pfInvalidThemeJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid theme JSON'**
  String get pfInvalidThemeJson;

  /// No description provided for @pfThemeApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied \"{name}\"'**
  String pfThemeApplied(String name);

  /// No description provided for @pfSaveTheme.
  ///
  /// In en, this message translates to:
  /// **'Save theme'**
  String get pfSaveTheme;

  /// No description provided for @pfThemeName.
  ///
  /// In en, this message translates to:
  /// **'Theme name'**
  String get pfThemeName;

  /// No description provided for @pfThemeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\"'**
  String pfThemeSaved(String name);

  /// No description provided for @pfCustomColour.
  ///
  /// In en, this message translates to:
  /// **'Custom colour'**
  String get pfCustomColour;

  /// No description provided for @pfHexHint.
  ///
  /// In en, this message translates to:
  /// **'Hex (e.g. #6E7BFF)'**
  String get pfHexHint;

  /// No description provided for @lgCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open the log folder: {error}'**
  String lgCouldNotOpen(String error);

  /// No description provided for @lgDiagnosticLogs.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic logs'**
  String get lgDiagnosticLogs;

  /// No description provided for @lgNotActive.
  ///
  /// In en, this message translates to:
  /// **'File logging is not active'**
  String get lgNotActive;

  /// No description provided for @lgReveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get lgReveal;

  /// No description provided for @pdEmpty.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet. Add one to set your commit identity.'**
  String get pdEmpty;

  /// No description provided for @pdUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get pdUse;

  /// No description provided for @pdDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete profile {label}?'**
  String pdDeleteTitle(String label);

  /// No description provided for @pdDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The profile is removed. Any keys it references in the keychain are left untouched.'**
  String get pdDeleteBody;

  /// No description provided for @pdAddProfile.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get pdAddProfile;

  /// No description provided for @pfmNew.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get pfmNew;

  /// No description provided for @pfmEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get pfmEdit;

  /// No description provided for @pfmProfileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get pfmProfileName;

  /// No description provided for @pfmProfileNameHint.
  ///
  /// In en, this message translates to:
  /// **'Work, Personal, …'**
  String get pfmProfileNameHint;

  /// No description provided for @pfmDeveloperName.
  ///
  /// In en, this message translates to:
  /// **'Developer name'**
  String get pfmDeveloperName;

  /// No description provided for @pfmDeveloperNameHint.
  ///
  /// In en, this message translates to:
  /// **'Your name in commits'**
  String get pfmDeveloperNameHint;

  /// No description provided for @pfmEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get pfmEmail;

  /// No description provided for @fpTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your first profile'**
  String get fpTitle;

  /// No description provided for @fpBody.
  ///
  /// In en, this message translates to:
  /// **'Every group and repository belongs to a profile. Switching profiles later shows only that profile’s work.'**
  String get fpBody;

  /// No description provided for @fpCreateProfile.
  ///
  /// In en, this message translates to:
  /// **'Create profile'**
  String get fpCreateProfile;

  /// No description provided for @mtCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get mtCurrent;

  /// No description provided for @mtCurrentNamed.
  ///
  /// In en, this message translates to:
  /// **'Current — {into}'**
  String mtCurrentNamed(String into);

  /// No description provided for @mtIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get mtIncoming;

  /// No description provided for @mtIncomingNamed.
  ///
  /// In en, this message translates to:
  /// **'Incoming — {branch}'**
  String mtIncomingNamed(String branch);

  /// No description provided for @mtNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'⚠ needs review'**
  String get mtNeedsReview;

  /// No description provided for @mtResolved.
  ///
  /// In en, this message translates to:
  /// **'✓ resolved'**
  String get mtResolved;

  /// No description provided for @mtBothAccepted.
  ///
  /// In en, this message translates to:
  /// **'Both accepted ⚠ needs review'**
  String get mtBothAccepted;

  /// No description provided for @mtAcceptBoth.
  ///
  /// In en, this message translates to:
  /// **'Accept both'**
  String get mtAcceptBoth;

  /// No description provided for @mtResult.
  ///
  /// In en, this message translates to:
  /// **'RESULT'**
  String get mtResult;

  /// No description provided for @mtUseEdit.
  ///
  /// In en, this message translates to:
  /// **'Use edit'**
  String get mtUseEdit;

  /// No description provided for @mtAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get mtAccept;

  /// No description provided for @rbPick.
  ///
  /// In en, this message translates to:
  /// **'keep this commit as it is'**
  String get rbPick;

  /// No description provided for @rbReword.
  ///
  /// In en, this message translates to:
  /// **'keep this commit, change its message'**
  String get rbReword;

  /// No description provided for @rbSquash.
  ///
  /// In en, this message translates to:
  /// **'merge into the commit above, keep both messages'**
  String get rbSquash;

  /// No description provided for @rbFixup.
  ///
  /// In en, this message translates to:
  /// **'merge into the commit above, drop its message'**
  String get rbFixup;

  /// No description provided for @rbDrop.
  ///
  /// In en, this message translates to:
  /// **'remove this commit entirely'**
  String get rbDrop;

  /// No description provided for @rbPresetAsIs.
  ///
  /// In en, this message translates to:
  /// **'Move commits as-is'**
  String get rbPresetAsIs;

  /// No description provided for @rbPresetSquashAll.
  ///
  /// In en, this message translates to:
  /// **'Squash into one commit'**
  String get rbPresetSquashAll;

  /// No description provided for @rbPresetSquashKeepFirst.
  ///
  /// In en, this message translates to:
  /// **'Squash, keep first message'**
  String get rbPresetSquashKeepFirst;

  /// No description provided for @rbSummaryAsIs.
  ///
  /// In en, this message translates to:
  /// **'Replay all {count} commits on the new base. History keeps its shape.'**
  String rbSummaryAsIs(int count);

  /// No description provided for @rbSummarySquashAll.
  ///
  /// In en, this message translates to:
  /// **'Combine all {count} into one commit; all messages are kept, one after another.'**
  String rbSummarySquashAll(int count);

  /// No description provided for @rbSummarySquashKeepFirst.
  ///
  /// In en, this message translates to:
  /// **'Combine all {count} into one commit; only the first message is kept.'**
  String rbSummarySquashKeepFirst(int count);

  /// No description provided for @rbTitle.
  ///
  /// In en, this message translates to:
  /// **'Interactive rebase'**
  String get rbTitle;

  /// No description provided for @rbCommitCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} commit} other{{count} commits}}'**
  String rbCommitCount(int count);

  /// No description provided for @rbCommitCountOnto.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} commit onto {onto}} other{{count} commits onto {onto}}}'**
  String rbCommitCountOnto(int count, String onto);

  /// No description provided for @rbStart.
  ///
  /// In en, this message translates to:
  /// **'Start rebase'**
  String get rbStart;

  /// No description provided for @rbNeedsTwo.
  ///
  /// In en, this message translates to:
  /// **'Needs at least 2 commits.'**
  String get rbNeedsTwo;

  /// No description provided for @rbCustomize.
  ///
  /// In en, this message translates to:
  /// **'Customize per commit'**
  String get rbCustomize;

  /// No description provided for @rbCustomizeHint.
  ///
  /// In en, this message translates to:
  /// **'Pick an action for each commit, or drag to reorder them.'**
  String get rbCustomizeHint;

  /// No description provided for @dlgEditCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit commit message'**
  String get dlgEditCommitMessage;

  /// No description provided for @dlgUnsavedOne.
  ///
  /// In en, this message translates to:
  /// **'{path} has changes that are not on disk.'**
  String dlgUnsavedOne(String path);

  /// No description provided for @dlgUnsavedMany.
  ///
  /// In en, this message translates to:
  /// **'These files have changes that are not on disk:'**
  String get dlgUnsavedMany;

  /// No description provided for @fteConflictBody.
  ///
  /// In en, this message translates to:
  /// **'Something else wrote {name} while it was open here. Saving replaces those changes with this text.'**
  String fteConflictBody(String name);

  /// No description provided for @fteCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open this file'**
  String get fteCouldNotOpen;

  /// No description provided for @fteNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get fteNoResults;

  /// No description provided for @fteFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get fteFind;

  /// No description provided for @fteReplaceWith.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get fteReplaceWith;

  /// No description provided for @fteMatchCase.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get fteMatchCase;

  /// No description provided for @ftePreviousMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get ftePreviousMatch;

  /// No description provided for @fteNextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get fteNextMatch;

  /// No description provided for @fteReplaceThis.
  ///
  /// In en, this message translates to:
  /// **'Replace this match'**
  String get fteReplaceThis;

  /// No description provided for @fteReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get fteReplaceAll;

  /// No description provided for @diffEditingWorkingTree.
  ///
  /// In en, this message translates to:
  /// **'Editing the working tree — saved changes stay unstaged'**
  String get diffEditingWorkingTree;

  /// No description provided for @diffStageSelectedLines.
  ///
  /// In en, this message translates to:
  /// **'Stage selected lines'**
  String get diffStageSelectedLines;

  /// No description provided for @diffUnstageSelectedLines.
  ///
  /// In en, this message translates to:
  /// **'Unstage selected lines'**
  String get diffUnstageSelectedLines;

  /// No description provided for @diffDiscardSelectedLines.
  ///
  /// In en, this message translates to:
  /// **'Discard selected lines'**
  String get diffDiscardSelectedLines;

  /// No description provided for @diffUnsavedBody.
  ///
  /// In en, this message translates to:
  /// **'What you typed in {path} has not been written to the working tree.'**
  String diffUnsavedBody(String path);

  /// No description provided for @diffUncommittedWorkingTree.
  ///
  /// In en, this message translates to:
  /// **'Uncommitted changes · working tree'**
  String get diffUncommittedWorkingTree;

  /// No description provided for @diffStageFile.
  ///
  /// In en, this message translates to:
  /// **'Stage file'**
  String get diffStageFile;

  /// No description provided for @diffUnstageFile.
  ///
  /// In en, this message translates to:
  /// **'Unstage file'**
  String get diffUnstageFile;

  /// No description provided for @diffShowChangesOnly.
  ///
  /// In en, this message translates to:
  /// **'Show changes only'**
  String get diffShowChangesOnly;

  /// No description provided for @diffShowWholeFile.
  ///
  /// In en, this message translates to:
  /// **'Show whole file'**
  String get diffShowWholeFile;

  /// No description provided for @diffCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load diff'**
  String get diffCouldNotLoad;

  /// No description provided for @diffBinaryFile.
  ///
  /// In en, this message translates to:
  /// **'Binary file — diff not shown'**
  String get diffBinaryFile;

  /// No description provided for @diffCouldNotStage.
  ///
  /// In en, this message translates to:
  /// **'Could not stage'**
  String get diffCouldNotStage;

  /// No description provided for @diffCouldNotUnstage.
  ///
  /// In en, this message translates to:
  /// **'Could not unstage'**
  String get diffCouldNotUnstage;

  /// No description provided for @diffCouldNotDiscard.
  ///
  /// In en, this message translates to:
  /// **'Could not discard'**
  String get diffCouldNotDiscard;

  /// No description provided for @diffStageHunk.
  ///
  /// In en, this message translates to:
  /// **'Stage hunk'**
  String get diffStageHunk;

  /// No description provided for @diffUnstageHunk.
  ///
  /// In en, this message translates to:
  /// **'Unstage hunk'**
  String get diffUnstageHunk;

  /// No description provided for @diffDiscardHunk.
  ///
  /// In en, this message translates to:
  /// **'Discard hunk'**
  String get diffDiscardHunk;

  /// No description provided for @diffUnstagedLabel.
  ///
  /// In en, this message translates to:
  /// **'Unstaged'**
  String get diffUnstagedLabel;

  /// No description provided for @diffStagedLabel.
  ///
  /// In en, this message translates to:
  /// **'Staged'**
  String get diffStagedLabel;

  /// No description provided for @fepOpenAFile.
  ///
  /// In en, this message translates to:
  /// **'Open a file to edit it'**
  String get fepOpenAFile;

  /// No description provided for @fepDeletedOnDisk.
  ///
  /// In en, this message translates to:
  /// **'Deleted on disk — saving is disabled'**
  String get fepDeletedOnDisk;

  /// No description provided for @pnpNavigator.
  ///
  /// In en, this message translates to:
  /// **'project navigator'**
  String get pnpNavigator;

  /// No description provided for @pnpNewFileMenu.
  ///
  /// In en, this message translates to:
  /// **'New file…'**
  String get pnpNewFileMenu;

  /// No description provided for @pnpNewFolderMenu.
  ///
  /// In en, this message translates to:
  /// **'New folder…'**
  String get pnpNewFolderMenu;

  /// No description provided for @pnpRenameMenu.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get pnpRenameMenu;

  /// No description provided for @pnpDeleteMenu.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get pnpDeleteMenu;

  /// No description provided for @pnpStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get pnpStage;

  /// No description provided for @pnpUnstage.
  ///
  /// In en, this message translates to:
  /// **'Unstage'**
  String get pnpUnstage;

  /// No description provided for @pnpDiscardMenu.
  ///
  /// In en, this message translates to:
  /// **'Discard changes…'**
  String get pnpDiscardMenu;

  /// No description provided for @pnpShowHistory.
  ///
  /// In en, this message translates to:
  /// **'Show history'**
  String get pnpShowHistory;

  /// No description provided for @pnpRevealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get pnpRevealInFinder;

  /// No description provided for @pnpShowInExplorer.
  ///
  /// In en, this message translates to:
  /// **'Show in Explorer'**
  String get pnpShowInExplorer;

  /// No description provided for @pnpOpenContainingFolder.
  ///
  /// In en, this message translates to:
  /// **'Open containing folder'**
  String get pnpOpenContainingFolder;

  /// No description provided for @pnpNewFile.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get pnpNewFile;

  /// No description provided for @pnpNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get pnpNewFolder;

  /// No description provided for @pnpDeleteFolderBody.
  ///
  /// In en, this message translates to:
  /// **'The folder and everything in it is removed from disk, not just from git.'**
  String get pnpDeleteFolderBody;

  /// No description provided for @pnpDeleteFileBody.
  ///
  /// In en, this message translates to:
  /// **'The file is removed from disk, not just from git.'**
  String get pnpDeleteFileBody;

  /// No description provided for @pnpDiscardUntrackedBody.
  ///
  /// In en, this message translates to:
  /// **'The file is untracked, so discarding deletes it.'**
  String get pnpDiscardUntrackedBody;

  /// No description provided for @pnpDiscardTrackedBody.
  ///
  /// In en, this message translates to:
  /// **'The file goes back to what it was at the last commit.'**
  String get pnpDiscardTrackedBody;

  /// No description provided for @pnpCouldNotOpenFileManager.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file manager'**
  String get pnpCouldNotOpenFileManager;

  /// No description provided for @pnpOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get pnpOperationFailed;

  /// No description provided for @pnpMore.
  ///
  /// In en, this message translates to:
  /// **'…{count} more'**
  String pnpMore(int count);

  /// No description provided for @pnpProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get pnpProject;

  /// No description provided for @pnpShowIgnored.
  ///
  /// In en, this message translates to:
  /// **'Show ignored files'**
  String get pnpShowIgnored;

  /// No description provided for @pnpHideIgnored.
  ///
  /// In en, this message translates to:
  /// **'Hide ignored files'**
  String get pnpHideIgnored;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
