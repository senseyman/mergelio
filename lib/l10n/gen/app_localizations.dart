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
