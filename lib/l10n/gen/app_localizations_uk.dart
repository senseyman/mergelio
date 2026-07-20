// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'Mergelio';

  @override
  String get cancel => 'Скасувати';

  @override
  String get save => 'Зберегти';

  @override
  String get delete => 'Видалити';

  @override
  String get close => 'Закрити';

  @override
  String get apply => 'Застосувати';

  @override
  String get import => 'Імпорт';

  @override
  String get export => 'Експорт';

  @override
  String get tooltipTerminal => 'Термінал (⌘`)';

  @override
  String get tooltipSearch => 'Пошук (⌘F)';

  @override
  String get tooltipPalette => 'Палітра команд (⌘K)';

  @override
  String get tooltipPreferences => 'Налаштування (⌘,)';

  @override
  String get tooltipProfiles => 'Профілі';

  @override
  String get opFetch => 'Отримати';

  @override
  String get opPull => 'Стягнути';

  @override
  String get opPullRebase => 'Стягнути (rebase)';

  @override
  String get opPush => 'Надіслати';

  @override
  String get opPushOrigin => 'Надіслати origin';

  @override
  String get opForcePush => 'Примусово надіслати (with lease)';

  @override
  String get opUndo => 'Скасувати';

  @override
  String get opRedo => 'Повторити';

  @override
  String get welcomeOpen => 'Відкрити';

  @override
  String get welcomeClone => 'Клонувати';

  @override
  String get welcomeCreate => 'Створити';

  @override
  String get welcomeRecents => 'Нещодавні репозиторії';

  @override
  String get welcomeNoRecents => 'Ще немає нещодавніх репозиторіїв';

  @override
  String get prefsTitle => 'Налаштування';

  @override
  String get prefsTabGeneral => 'Загальні';

  @override
  String get prefsTabAppearance => 'Вигляд';

  @override
  String get prefsTabShortcuts => 'Комбінації клавіш';

  @override
  String get prefsTabCredentials => 'Облікові дані';

  @override
  String get prefsAutoFetch => 'Автоотримання';

  @override
  String get prefsConfirmDestructive => 'Підтверджувати руйнівні дії';

  @override
  String get prefsRestoreTabs => 'Відновлювати вкладки при запуску';

  @override
  String get prefsTelemetry => 'Надсилати анонімні дані про використання';

  @override
  String get prefsZoom => 'Масштаб';

  @override
  String get prefsGroupStyle => 'Перемикач груп';

  @override
  String get prefsPullStrategy => 'Стратегія стягування';

  @override
  String get prefsDateFormat => 'Формат дати';

  @override
  String get prefsGraphColumns => 'Колонки графа';

  @override
  String get prefsCompactRows => 'Компактні рядки';

  @override
  String get prefsLanguage => 'Мова';

  @override
  String get prefsTheme => 'Тема';

  @override
  String get prefsAccent => 'Акцент';

  @override
  String get prefsBranchColours => 'Кольори гілок';

  @override
  String get prefsResetColours => 'Скинути кольори';

  @override
  String get prefsSavedThemes => 'Збережені теми';

  @override
  String get prefsSaveCurrent => 'Зберегти поточну…';

  @override
  String get strategyMerge => 'злиття';

  @override
  String get strategyRebase => 'rebase';

  @override
  String get dateMedium => 'середній';

  @override
  String get dateIso => 'ISO';

  @override
  String get dateShort => 'короткий';

  @override
  String get themeDark => 'темна';

  @override
  String get themeLight => 'світла';

  @override
  String get themeSystem => 'системна';

  @override
  String get languageSystem => 'Системна';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get graphHistory => 'ІСТОРІЯ';

  @override
  String get graphCompact => 'Компактно';

  @override
  String get filterHideMerges => 'Сховати злиття';

  @override
  String get filterHideTags => 'Сховати теги';

  @override
  String get menuCheckout => 'Переключитися на цей коміт';

  @override
  String get menuCreateBranch => 'Створити гілку тут';

  @override
  String get menuCreateTag => 'Створити тег тут';

  @override
  String get menuCherryPick => 'Cherry-pick';

  @override
  String get menuRevert => 'Відкотити';

  @override
  String get menuRebaseHere => 'Rebase сюди…';

  @override
  String get menuResetHard => 'Скинути сюди (--hard)';

  @override
  String get menuCopySha => 'Копіювати SHA';

  @override
  String a11yCommitRow(String sha, String author, String message) {
    return 'Коміт $sha від $author: $message';
  }

  @override
  String get a11yWorkingChanges => 'Зміни в робочому дереві';

  @override
  String get a11yCommitGraph => 'Граф історії комітів';
}
