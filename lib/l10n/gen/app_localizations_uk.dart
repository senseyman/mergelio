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
  String get tooltipProjectFiles => 'Файли проєкту';

  @override
  String get tooltipHistory => 'Історія';

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
  String get prefsAutoFetchInterval => 'Інтервал автоотримання';

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
  String get prefsClockFormat => 'Годинник';

  @override
  String get clock24 => '24-годинний';

  @override
  String get clock12 => '12-годинний';

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
  String get filterContentRegex => 'Regex';

  @override
  String get searchContentHint => 'У змінах…';

  @override
  String get searchContentHelp => 'Коміти, які додали або видалили цей текст';

  @override
  String get searchContentRegexHelp =>
      'Коміти з доданим або видаленим рядком, що відповідає цьому регулярному виразу';

  @override
  String get searchRunning => 'Пошук…';

  @override
  String get searchNoMatches => 'Немає збігів';

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
  String get menuEditMessage => 'Редагувати опис…';

  @override
  String get menuCopySummary => 'Копіювати заголовок';

  @override
  String get menuCopyDescription => 'Копіювати опис';

  @override
  String get menuCopyMessage => 'Копіювати повідомлення';

  @override
  String get menuCopySha => 'Копіювати SHA';

  @override
  String get rewordTitle => 'Редагувати повідомлення коміту';

  @override
  String get rewordPushedTitle => 'Переписати відправлений коміт?';

  @override
  String rewordPushedBody(String branches) {
    return 'Цей коміт уже є в $branches. Зміна повідомлення переписує історію, тож гілку доведеться відправити примусово, а всі, хто її отримав, муситимуть зробити reset.';
  }

  @override
  String get rewordPushedConfirm => 'Все одно переписати';

  @override
  String get mergeResolveConflicts => 'Вирішити конфлікти';

  @override
  String get mergeRebase => 'Rebase';

  @override
  String mergeCherryPick(String sha) {
    return 'Cherry-pick $sha';
  }

  @override
  String mergeRevert(String sha) {
    return 'Відкотити $sha';
  }

  @override
  String mergeInto(String branch, String into) {
    return 'Злиття $branch → $into';
  }

  @override
  String mergeBranch(String branch) {
    return 'Злиття $branch';
  }

  @override
  String mergeResolvedCount(int resolved, int total) {
    return '$resolved / $total вирішено';
  }

  @override
  String get mergeNextUnresolved => 'Наступний невирішений';

  @override
  String get mergeAbort => 'Перервати';

  @override
  String get mergeResolve => 'Вирішити';

  @override
  String a11yCommitRow(String sha, String author, String message) {
    return 'Коміт $sha від $author: $message';
  }

  @override
  String get a11yWorkingChanges => 'Зміни в робочому дереві';

  @override
  String get a11yCommitGraph => 'Граф історії комітів';

  @override
  String get shellAddRepository => 'Додати репозиторій';

  @override
  String get shellOpenRepoMenu => 'Відкрити…';

  @override
  String get shellCloneRepoMenu => 'Клонувати…';

  @override
  String get shellCreateRepoMenu => 'Створити…';

  @override
  String get shellRepoGroup => 'Група репозиторіїв';

  @override
  String get shellAllGroups => 'Усі';

  @override
  String get shellNewGroup => 'Нова група';

  @override
  String get shellNewGroupMenu => 'Нова група…';

  @override
  String get shellGroupName => 'Назва групи';

  @override
  String get shellRenameGroup => 'Перейменувати групу';

  @override
  String get shellRenameMenu => 'Перейменувати…';

  @override
  String get shellRenameGroupMenu => 'Перейменувати групу…';

  @override
  String get shellDeleteGroupTitle => 'Видалити групу?';

  @override
  String get shellDeleteGroupMenu => 'Видалити групу…';

  @override
  String shellDeleteGroupBody(String name) {
    return '«$name» буде вилучено з перемикача. Репозиторії з неї залишаться відкритими, але без групи.';
  }

  @override
  String get shellCloseTab => 'Закрити вкладку';

  @override
  String get shellCloseOthers => 'Закрити інші';

  @override
  String shellRemoveFromGroup(String name) {
    return 'Вилучити з $name';
  }

  @override
  String shellMoveToGroup(String name) {
    return 'Перемістити до $name';
  }

  @override
  String get tabWorktree => 'Робоче дерево';

  @override
  String tabWorktreeOf(String parent) {
    return 'Робоче дерево $parent';
  }

  @override
  String get wtAdd => 'Додати робоче дерево';

  @override
  String get wtLocation => 'Розташування';

  @override
  String get wtBrowse => 'Огляд…';

  @override
  String get wtNewBranch => 'Нова гілка';

  @override
  String get wtFrom => 'від';

  @override
  String get wtExistingBranch => 'Наявна гілка';

  @override
  String get wtDetachedAt => 'Відокремлено на';

  @override
  String wtHeldBy(String name) {
    return '— у $name';
  }

  @override
  String get wtBranchExists => 'Така гілка вже існує';

  @override
  String get wtDirNotEmpty => 'Ця тека не порожня';

  @override
  String get wtSubmodulesNote =>
      'Підмодулі не отримуються в новому робочому дереві; ініціалізуйте їх там самостійно.';

  @override
  String get wtOpenInNewTab => 'Відкрити в новій вкладці';

  @override
  String get wtRemoveTitle => 'Видалити робоче дерево?';

  @override
  String wtCheckedOutBranch(String branch) {
    return 'Переключено на: $branch';
  }

  @override
  String get wtDirDeleted => 'Теку буде видалено.';

  @override
  String get wtRemove => 'Видалити';

  @override
  String get wtHasChangesTitle => 'Робоче дерево має зміни';

  @override
  String get wtForcingDiscards => 'Примусове видалення відкине ці зміни.';

  @override
  String get wtForceRemove => 'Видалити примусово';

  @override
  String get wtMoveTitle => 'Перемістити робоче дерево';

  @override
  String get wtAlreadyThere => 'Воно вже там';

  @override
  String wtNewLocationFor(String name) {
    return 'Нове розташування для $name';
  }

  @override
  String get wtMove => 'Перемістити';

  @override
  String get wtAlreadyCheckedOut => 'Уже переключено';

  @override
  String wtCheckedOutInWorktreeAt(String branch) {
    return 'Гілку $branch використовує робоче дерево за шляхом';
  }

  @override
  String get wtTwoPlacesWarning =>
      'Перемикання попри це розмістить гілку у двох місцях одночасно; коміти, зроблені в одному, залишать інше позаду.';

  @override
  String get wtCheckoutAnyway => 'Усе одно переключитися';

  @override
  String get wtOpenWorktree => 'Відкрити робоче дерево';

  @override
  String get wtPruneTitle => 'Очистити застарілі робочі дерева';

  @override
  String get wtNothingToPrune => 'Нема чого очищати.';

  @override
  String get wtEntriesWillBeRemoved => 'Ці записи буде видалено:';

  @override
  String get wtPrune => 'Очистити';

  @override
  String get sbRepository => 'Репозиторій';

  @override
  String get sbCollapse => 'Згорнути';

  @override
  String get sbCouldNotRead => 'Не вдалося прочитати репозиторій';

  @override
  String get sbRetry => 'Повторити';

  @override
  String get sbBranches => 'Гілки';

  @override
  String get sbNoBranches => 'Немає гілок';

  @override
  String get sbRemotes => 'Віддалені репозиторії';

  @override
  String get sbNoRemotes => 'Немає віддалених репозиторіїв';

  @override
  String get sbTags => 'Теги';

  @override
  String get sbNoTags => 'Немає тегів';

  @override
  String get sbStashes => 'Схованки';

  @override
  String get sbNoStashes => 'Немає схованок';

  @override
  String get sbSubmodules => 'Підмодулі';

  @override
  String get sbNoSubmodules => 'Немає підмодулів';

  @override
  String get sbAddRemoteRow => 'Додати віддалений…';

  @override
  String get sbAddRemoteTitle => 'Додати віддалений';

  @override
  String get sbAdd => 'Додати';

  @override
  String get sbAddSubmoduleRow => 'Додати підмодуль…';

  @override
  String get sbPop => 'Дістати';

  @override
  String get sbInit => 'Ініціалізувати';

  @override
  String get sbUpdate => 'Оновити';

  @override
  String get sbUpdateToRemote => 'Оновити до віддаленого';

  @override
  String get sbSync => 'Синхронізувати';

  @override
  String get sbDeinit => 'Деініціалізувати';

  @override
  String get sbReset => 'Скинути';

  @override
  String sbResetToUpstreamTitle(String branch, String upstream) {
    return 'Скинути $branch до $upstream?';
  }

  @override
  String sbResetUnpushedBody(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count невідправлених комітів у $branch буде вилучено. Цю дію можна скасувати.',
      few:
          '$count невідправлені коміти у $branch буде вилучено. Цю дію можна скасувати.',
      one:
          '$count невідправлений коміт у $branch буде вилучено. Цю дію можна скасувати.',
    );
    return '$_temp0';
  }

  @override
  String sbResetMovedBody(String branch, String upstream) {
    return '$branch буде переміщено до $upstream. Цю дію можна скасувати.';
  }

  @override
  String get sbCheckout => 'Переключитися';

  @override
  String get sbMergeIntoCurrent => 'Злити в поточну';

  @override
  String get sbRebaseOntoCurrent => 'Перебазувати на поточну';

  @override
  String get sbSetUpstreamItem => 'Встановити відстеження…';

  @override
  String sbSetUpstreamTitle(String branch) {
    return 'Відстеження для $branch';
  }

  @override
  String sbSetUpstreamHint(String branch) {
    return 'напр. origin/$branch';
  }

  @override
  String get sbResetToRemote => 'Скинути до віддаленої…';

  @override
  String get sbRenameItem => 'Перейменувати…';

  @override
  String get sbRenameBranchTitle => 'Перейменувати гілку';

  @override
  String get sbDeleteBranch => 'Видалити гілку';

  @override
  String sbDeleteBranchTitle(String branch) {
    return 'Видалити $branch?';
  }

  @override
  String get sbDeleteBranchBody =>
      'Посилання на гілку буде вилучено. Цю дію можна скасувати.';

  @override
  String get sbDeleteBranchAndRemote => 'Видалити гілку та віддалену…';

  @override
  String sbDeleteBothTitle(String branch, String upstream) {
    return 'Видалити $branch і $upstream?';
  }

  @override
  String get sbDeleteBothBody =>
      'Гілку буде вилучено тут і на віддаленому репозиторії. Скасувати можна лише локальну половину.';

  @override
  String get sbDeleteBoth => 'Видалити обидві';

  @override
  String sbCheckedOutIn(String name) {
    return 'Використовується в $name';
  }

  @override
  String sbMergeSourceInto(String source, String target) {
    return 'Злити «$source» у «$target»';
  }

  @override
  String sbRebaseSourceOnto(String source, String target) {
    return 'Перебазувати «$source» на «$target»';
  }

  @override
  String sbTipSwitchHint(String branch) {
    return 'Клацніть, щоб показати вершину · подвійне клацання — переключитися на $branch';
  }

  @override
  String sbTipCheckoutHint(String name) {
    return 'Клацніть, щоб показати вершину · подвійне клацання — отримати $name';
  }

  @override
  String get sbHasLocalBranch => 'Має локальну гілку';

  @override
  String sbSwitchTo(String branch) {
    return 'Переключитися на $branch';
  }

  @override
  String sbCheckOutNamed(String name) {
    return 'Отримати $name';
  }

  @override
  String sbMergeNamedIntoCurrent(String name) {
    return 'Злити $name у поточну';
  }

  @override
  String sbResetToThis(String branch) {
    return 'Скинути $branch до цього';
  }

  @override
  String sbDeleteRemoteBranchTitle(String name) {
    return 'Видалити $name?';
  }

  @override
  String sbDeleteRemoteBranchBody(String remote) {
    return 'Гілку буде видалено на $remote. Локальна гілка з такою ж назвою залишиться. Цю дію не можна скасувати.';
  }

  @override
  String sbDeleteNamedItem(String name) {
    return 'Видалити $name…';
  }

  @override
  String sbFetchRemote(String remote) {
    return 'Отримати з $remote';
  }

  @override
  String get sbPrune => 'Очистити';

  @override
  String get sbCopyUrl => 'Копіювати URL';

  @override
  String get sbEditRemoteTitle => 'Редагувати віддалений';

  @override
  String get sbEditRemoteItem => 'Редагувати віддалений…';

  @override
  String sbRemoveRemoteTitle(String remote) {
    return 'Вилучити віддалений $remote?';
  }

  @override
  String get sbRemoveRemoteBody =>
      'Його гілки відстеження зникнуть разом із ним. Скасування відновить віддалений; отримайте зміни, щоб повернути гілки.';

  @override
  String get sbRemove => 'Вилучити';

  @override
  String get sbRemoveRemoteItem => 'Вилучити віддалений…';

  @override
  String get sbPushTag => 'Відправити тег';

  @override
  String get sbCopyName => 'Копіювати назву';

  @override
  String sbDeleteTagTitle(String tag) {
    return 'Видалити тег $tag?';
  }

  @override
  String get sbDeleteTagBody =>
      'Тег буде вилучено локально. Цю дію можна скасувати.';

  @override
  String get sbDeleteTag => 'Видалити тег';

  @override
  String sbDropStashTitle(String ref) {
    return 'Відкинути $ref?';
  }

  @override
  String get sbDropStashBody =>
      'Схованку буде видалено. Спливне сповіщення дозволить її відновити.';

  @override
  String get sbDrop => 'Відкинути';

  @override
  String sbRemoveSubmoduleTitle(String name) {
    return 'Вилучити $name?';
  }

  @override
  String sbRemoveSubmoduleBody(String path) {
    return 'Підмодуль за шляхом $path буде деініціалізовано та вилучено з .gitmodules. Цю дію не можна скасувати.';
  }
}
