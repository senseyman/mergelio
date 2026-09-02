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
  String get opPullRebase => 'Стягнути (перебазувати)';

  @override
  String get opPush => 'Відправити';

  @override
  String get opPushOrigin => 'Відправити в origin';

  @override
  String get opForcePush => 'Примусово відправити (with lease)';

  @override
  String get welcomeOpen => 'Відкрити';

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
  String get prefsGraphColumns => 'Стовпці графа';

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
  String get strategyRebase => 'перебазування';

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
  String get menuRebaseHere => 'Перебазувати сюди…';

  @override
  String get menuResetHard => 'Скинути сюди (--hard)';

  @override
  String get menuEditMessage => 'Редагувати повідомлення…';

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
  String get mergeRebase => 'Перебазувати';

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
    return 'Робоче дерево репозиторію $parent';
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
      'Перемикання попри це розмістить гілку у двох місцях одночасно; коміти, зроблені в одному, не потраплять до іншого.';

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
          '$count невідправленого коміта у $branch буде вилучено. Цю дію можна скасувати.',
      many:
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
    return 'Клацніть, щоб показати вершину · подвійне клацання — переключитися на $name';
  }

  @override
  String get sbHasLocalBranch => 'Має локальну гілку';

  @override
  String sbSwitchTo(String branch) {
    return 'Переключитися на $branch';
  }

  @override
  String sbCheckOutNamed(String name) {
    return 'Переключитися на $name';
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
    return 'Вилучити $ref?';
  }

  @override
  String get sbDropStashBody =>
      'Схованку буде видалено. Спливне сповіщення дозволить її відновити.';

  @override
  String get sbDrop => 'Вилучити';

  @override
  String sbRemoveSubmoduleTitle(String name) {
    return 'Вилучити $name?';
  }

  @override
  String sbRemoveSubmoduleBody(String path) {
    return 'Підмодуль за шляхом $path буде деініціалізовано та вилучено з .gitmodules. Цю дію не можна скасувати.';
  }

  @override
  String get discard => 'Відкинути';

  @override
  String get create => 'Створити';

  @override
  String get edit => 'Редагувати';

  @override
  String get rename => 'Перейменувати';

  @override
  String get commonUnsavedChanges => 'Незбережені зміни';

  @override
  String get commonFileChangedOnDisk => 'Файл змінено на диску';

  @override
  String get commonOverwrite => 'Перезаписати';

  @override
  String get diffDiscardEditsTitle => 'Відкинути зміни?';

  @override
  String diffDiscardEditsBody(String path) {
    return 'Введений тут текст не було записано у $path.';
  }

  @override
  String get diffSelectAll => 'Вибрати все';

  @override
  String diffDiscardFileTitle(String path) {
    return 'Відкинути $path?';
  }

  @override
  String get diffDiscardFileBody =>
      'Це видалить невідстежуваний файл. Дію можна скасувати.';

  @override
  String get filesEditor => 'Редактор';

  @override
  String filesClosePath(String path) {
    return 'Закрити $path';
  }

  @override
  String get filesName => 'Назва';

  @override
  String get filesRenameTitle => 'Перейменувати';

  @override
  String get filesNewName => 'Нова назва';

  @override
  String filesDeleteTitle(String name) {
    return 'Видалити $name?';
  }

  @override
  String filesDiscardChangesTitle(String name) {
    return 'Відкинути зміни у $name?';
  }

  @override
  String get filesRefresh => 'Оновити';

  @override
  String get filesCollapse => 'Згорнути';

  @override
  String wtpAlsoDeleteUntracked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Також видалити $count невідстежуваного файла',
      many: 'Також видалити $count невідстежуваних файлів',
      few: 'Також видалити $count невідстежувані файли',
      one: 'Також видалити $count невідстежуваний файл',
    );
    return '$_temp0';
  }

  @override
  String get diffDiscardHunkTitle => 'Відкинути блок змін?';

  @override
  String diffDiscardLinesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Відкинути $count рядка?',
      many: 'Відкинути $count рядків?',
      few: 'Відкинути $count рядки?',
      one: 'Відкинути $count рядок?',
    );
    return '$_temp0';
  }

  @override
  String get diffDiscardLinesBody =>
      'Це вилучить вибрані зміни з робочого дерева. Дію можна скасувати.';

  @override
  String get bbOpenRepoFirst => 'Спершу відкрийте репозиторій';

  @override
  String get bbOperationRunning => 'Операція вже виконується';

  @override
  String get bbNoRemote => 'Віддалений репозиторій не налаштовано';

  @override
  String bbUndoLabelled(String label) {
    return 'Скасувати $label (⌘Z)';
  }

  @override
  String get bbUndo => 'Скасувати (⌘Z)';

  @override
  String bbRedoLabelled(String label) {
    return 'Повторити $label (⌘⇧Z)';
  }

  @override
  String get bbRedo => 'Повторити (⌘⇧Z)';

  @override
  String get bbFetchOrigin => 'Отримати з origin';

  @override
  String get bbFetchAllRemotes => 'Отримати з усіх віддалених';

  @override
  String get bbPullAllRemotes => 'Стягнути (усі віддалені)';

  @override
  String get bbForcePushTitle => 'Примусово відправити?';

  @override
  String get bbForcePushBody =>
      'Це перезапише віддалену гілку вашою локальною історією (через --force-with-lease, який усе одно відмовить, якщо віддалена гілка несподівано змінилася).';

  @override
  String get bbForcePush => 'Примусово відправити';

  @override
  String get bbBranch => 'Гілка';

  @override
  String get bbMerge => 'Злити';

  @override
  String get bbStash => 'Сховати';

  @override
  String get sbarNoProfile => 'Немає профілю';

  @override
  String get sbarNoRepository => 'Немає репозиторію';

  @override
  String get sbarDark => 'Темна';

  @override
  String get sbarLight => 'Світла';

  @override
  String sbarCancelBusy(String label) {
    return 'Скасувати $label';
  }

  @override
  String get tbComingLater => 'З’явиться на пізнішому етапі';

  @override
  String get tbTerminal => 'Термінал';

  @override
  String get tbGlobalSearch => 'Глобальний пошук';

  @override
  String get tbCommandPalette => 'Палітра команд';

  @override
  String get railExpand => 'Розгорнути';

  @override
  String gaCheckoutBranch(String name) {
    return 'Переключитися: $name';
  }

  @override
  String gaFlyToCommit(String sha, String message) {
    return 'Перейти до: $sha  $message';
  }

  @override
  String get rmcMomentsAgo => 'щойно';

  @override
  String rmcMinutesAgo(int minutes) {
    return '$minutes хв тому';
  }

  @override
  String rmcHoursAgo(int hours) {
    return '$hours год тому';
  }

  @override
  String rmcDaysAgo(int days) {
    return '$days дн. тому';
  }

  @override
  String get rmcNotFetched => 'Цей репозиторій ще нічого не отримував.';

  @override
  String rmcLastFetched(String age) {
    return 'Останнє отримання $age.';
  }

  @override
  String rmcMergeFrom(String remote) {
    return 'Злити з $remote?';
  }

  @override
  String rmcStaleWarning(String source, String remote) {
    return '$source — це гілка відстеження. Вона актуальна лише станом на останнє отримання з $remote.';
  }

  @override
  String get rmcMergeAsIs => 'Злити як є';

  @override
  String get rmcFetchAndMerge => 'Отримати і злити';

  @override
  String get ropCreateBranchTitle => 'Створити гілку';

  @override
  String get ropCurrentBranch => 'поточну гілку';

  @override
  String ropMergeIntoTitle(String branch) {
    return 'Злити в $branch';
  }

  @override
  String get ropCreateTagTitle => 'Створити тег';

  @override
  String get ropTagName => 'Назва тегу';

  @override
  String get ropType => 'Тип';

  @override
  String get ropTagMessage => 'Повідомлення тегу';

  @override
  String get ropStashChangesTitle => 'Сховати зміни';

  @override
  String get ropBranchName => 'Назва гілки';

  @override
  String get ropStartFrom => 'Почати від';

  @override
  String get ropCheckoutAfterCreating => 'Переключитися після створення';

  @override
  String get ropNoOtherBranches => 'Немає інших гілок для злиття.';

  @override
  String get ropBranchToMerge => 'Гілка для злиття';

  @override
  String get ropMerge => 'Злити';

  @override
  String get ropMessageOptional => 'Повідомлення (необов’язково)';

  @override
  String get ropOnlyStaged => 'Лише проіндексовані зміни';

  @override
  String get ropStash => 'Сховати';

  @override
  String get shellPrevOpUnfinished => 'Попередня операція могла не завершитися';

  @override
  String get wtpChanges => 'ЗМІНИ';

  @override
  String get wtpDiscardAll => 'Відкинути всі зміни';

  @override
  String get wtpUnstaged => 'НЕПРОІНДЕКСОВАНІ';

  @override
  String get wtpStageAll => 'Проіндексувати все';

  @override
  String get wtpStaged => 'ПРОІНДЕКСОВАНІ';

  @override
  String get wtpUnstageAll => 'Зняти індексацію з усього';

  @override
  String wtpAbortTitle(String name) {
    return 'Перервати $name?';
  }

  @override
  String wtpAbortBody(String name) {
    return 'Проіндексоване вирішення буде відкинуто, і репозиторій повернеться до стану, з якого почався $name.';
  }

  @override
  String get wtpAbort => 'Перервати';

  @override
  String wtpOpPausedBody(String name) {
    return '$name призупинено. Перегляньте проіндексовані файли, потім продовжте.';
  }

  @override
  String get wtpMergeOpenBody =>
      'Триває злиття. Перегляньте проіндексовані файли, потім зробіть коміт.';

  @override
  String wtpContinueOp(String name) {
    return 'Продовжити $name';
  }

  @override
  String get wtpTreeClean => 'Робоче дерево чисте';

  @override
  String get wtpNothingToCommit => 'Нема чого комітити';

  @override
  String wtpSectionCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get wtpFileHistory => 'Історія файлу';

  @override
  String get wtpBlame => 'Авторство';

  @override
  String get wtpDiscardChanges => 'Відкинути зміни';

  @override
  String get wtpFinishOpFirst => 'Спершу завершіть операцію';

  @override
  String get wtpFinishOpBody =>
      'Продовжте або перервіть її вище; коміт тут залишить решту послідовності незавершеною.';

  @override
  String get wtpMessageEmpty => 'Повідомлення коміту порожнє';

  @override
  String get wtpNothingStaged => 'Нічого не проіндексовано для коміту';

  @override
  String get wtpCommitted => 'Закомічено';

  @override
  String get wtpCommitFailed => 'Не вдалося зробити коміт';

  @override
  String get wtpSummary => 'Заголовок';

  @override
  String get wtpDescription => 'Опис';

  @override
  String get wtpCoauthorsHint => 'Співавтори: Ім’я <email>, Ім’я2 <email2>';

  @override
  String get wtpAmend => 'Виправити';

  @override
  String get wtpSign => 'Підписати';

  @override
  String get wtpAddCoauthor => '+ Співавтор';

  @override
  String get wtpCommit => 'Коміт';

  @override
  String get wtpDiscardAllTitle => 'Відкинути всі зміни?';

  @override
  String get wtpDiscardAllBody =>
      'Це поверне кожен відстежуваний файл до стану останнього коміту, відкинувши проіндексовані та непроіндексовані зміни. Дію можна скасувати.';

  @override
  String wtpDiscardFileTitle(String path) {
    return 'Відкинути зміни у $path?';
  }

  @override
  String get wtpDiscardFileBody =>
      'Це поверне файл до стану останнього коміту, відкинувши проіндексовані та непроіндексовані зміни. Дію можна скасувати.';

  @override
  String get wtsWorktrees => 'Робочі дерева';

  @override
  String get wtsNoWorktrees => 'Немає робочих дерев';

  @override
  String get wtsPruneMenu => 'Очистити застарілі робочі дерева…';

  @override
  String wtsLockTitle(String name) {
    return 'Заблокувати $name';
  }

  @override
  String get wtsReasonOptional => 'Причина (необов’язково)';

  @override
  String get wtsLock => 'Заблокувати';

  @override
  String get wtsLocked => 'Заблоковано';

  @override
  String get wtsPrunable => 'Можна очистити';

  @override
  String get wtsOpenInTab => 'Відкрити у вкладці';

  @override
  String get wtsRevealInFinder => 'Показати у Finder';

  @override
  String get wtsMoveMenu => 'Перемістити…';

  @override
  String get wtsUnlock => 'Розблокувати';

  @override
  String get wtsLockMenu => 'Заблокувати…';

  @override
  String get wtsRemoveMenu => 'Вилучити…';

  @override
  String get cdCommit => 'КОМІТ';

  @override
  String get cdWip => '‹ WIP';

  @override
  String get cdAuthor => 'Автор';

  @override
  String get cdDate => 'Дата';

  @override
  String get cdParent => 'Батьківський';

  @override
  String get cdCoauthored => 'Співавторство';

  @override
  String get cdChangedFiles => 'ЗМІНЕНІ ФАЙЛИ';

  @override
  String get cdCouldNotRead => 'Не вдалося прочитати зміни';

  @override
  String get cdNoChanges => 'Немає змін';

  @override
  String get cdSha => 'SHA';

  @override
  String get asdTitle => 'Додати підмодуль';

  @override
  String get asdRepoUrl => 'URL репозиторію';

  @override
  String get asdPath => 'Шлях';

  @override
  String get asdPathHint => 'тека в цьому репозиторії';

  @override
  String get asdBranchOptional => 'Гілка (необов’язково)';

  @override
  String get asdBranchHint => 'відстежувати гілку';

  @override
  String get rdName => 'Назва';

  @override
  String get rdUrl => 'URL';

  @override
  String bsResetTitle(String branch, String target) {
    return 'Скинути $branch до $target?';
  }

  @override
  String bsResetBody(String branch, String target) {
    return 'Це перемістить локальну $branch до $target, відкинувши коміти, яких немає на віддаленому. Незакомічені зміни буде сховано (з можливістю повернення).';
  }

  @override
  String get bsResetAndSwitch => 'Скинути й переключитися';

  @override
  String get wvChanges => 'Зміни';

  @override
  String get wvChangesSub => 'Робоче дерево · індексація · коміт';

  @override
  String get rdlgCloneTitle => 'Клонувати репозиторій';

  @override
  String get rdlgCreateTitle => 'Створити репозиторій';

  @override
  String get rdlgFolderName => 'Назва теки';

  @override
  String get rdlgFolderHint => 'походить з URL';

  @override
  String get rdlgDestFolder => 'Тека призначення';

  @override
  String get rdlgCloning => 'Клонування…';

  @override
  String get rdlgClone => 'Клонувати';

  @override
  String get rdlgRepoName => 'Назва репозиторію';

  @override
  String get rdlgParentFolder => 'Батьківська тека';

  @override
  String get rdlgDefaultBranch => 'Типова гілка';

  @override
  String get rdlgInitReadme => 'Створити з README.md';

  @override
  String get rdlgAddGitignore => 'Додати порожній .gitignore';

  @override
  String get rdlgCreating => 'Створення…';

  @override
  String get rdlgChooseFolder => 'Виберіть теку…';

  @override
  String get rdlgBrowse => 'Огляд';

  @override
  String get welTitle => 'Ласкаво просимо до Mergelio';

  @override
  String get welSubtitle => 'Безкоштовний візуальний клієнт Git. Почніть:';

  @override
  String get welCloneSub => 'З URL (HTTPS/SSH) у теку';

  @override
  String get welCreateSub => 'Новий локальний репозиторій з README/.gitignore';

  @override
  String get welOpenTitle => 'Відкрити репозиторій';

  @override
  String get welOpenSub => 'Виберіть наявну теку з .git';

  @override
  String get welUnpin => 'Відкріпити';

  @override
  String get welPin => 'Закріпити';

  @override
  String get welRemoveRecent => 'Прибрати з нещодавніх';

  @override
  String get welNotARepo => 'Це не репозиторій git';

  @override
  String get gvSearchCommits => 'Пошук комітів…';

  @override
  String get gvAuthorFilter => 'Автор…';

  @override
  String get gvPrevMatch => 'Попередній (⇧N)';

  @override
  String get gvNextMatch => 'Наступний (N)';

  @override
  String get gvCloseSearch => 'Закрити (Esc)';

  @override
  String get gvColumns => 'Стовпці';

  @override
  String gvUncommittedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Незакомічені зміни · $count файла',
      many: 'Незакомічені зміни · $count файлів',
      few: 'Незакомічені зміни · $count файли',
      one: 'Незакомічені зміни · $count файл',
    );
    return '$_temp0';
  }

  @override
  String get gvCannotRebaseTitle => 'Неможливо перебазувати на цей коміт';

  @override
  String gvCannotRebaseBody(String sha) {
    return 'Коміти вище $sha містять злиття, яке перебазування розгорнуло б у лінійну історію.';
  }

  @override
  String get gvNothingToRebaseTitle => 'Нема чого перебазовувати';

  @override
  String gvNothingToRebaseBody(String sha) {
    return '$sha вже є частиною цієї гілки, і план нічого не змінює.';
  }

  @override
  String gvResetTitle(String sha) {
    return 'Скинути до $sha?';
  }

  @override
  String get gvResetBody =>
      'Переміщує поточну гілку на цей коміт і відкидає всі незакомічені зміни. Їх буде втрачено безповоротно.';

  @override
  String get gvResetHard => 'Reset --hard';

  @override
  String get ccBranch => 'Гілка';

  @override
  String get cpTypeCommand => 'Введіть команду…';

  @override
  String get termClose => 'Закрити термінал (⌘`)';

  @override
  String get fiHistory => 'Історія';

  @override
  String get fiCouldNotLoad => 'Не вдалося завантажити історію';

  @override
  String get fiCouldNotBlame => 'Не вдалося визначити авторство цього файлу';

  @override
  String get ftvFlatList => 'Показати плоским списком';

  @override
  String get ftvGroupByFolder => 'Групувати за текою';

  @override
  String get confirmAction => 'Підтвердити';

  @override
  String get pfScCommandPalette => 'Палітра команд';

  @override
  String get pfScSearchCommits => 'Пошук комітів';

  @override
  String get pfScNextPrevMatch => 'Наступний / попередній збіг';

  @override
  String get pfScCommit => 'Коміт (у редакторі)';

  @override
  String get pfScCreateBranch => 'Створити гілку';

  @override
  String get pfScCollapsePanel => 'Згорнути ліву панель';

  @override
  String get pfScToggleTerminal => 'Показати/сховати термінал';

  @override
  String get pfScZoom => 'Збільшити / зменшити';

  @override
  String get pfScResetZoom => 'Скинути масштаб';

  @override
  String get pfScUndo => 'Скасувати останню дію';

  @override
  String get pfScRedo => 'Повторити';

  @override
  String get pfScPreferences => 'Налаштування';

  @override
  String get pfScCloseDialog => 'Закрити діалог / скасувати';

  @override
  String get pfGenerateSshKey => 'Згенерувати ключ SSH';

  @override
  String pfAddPassphraseHint(String name) {
    return 'Виконайте ssh-keygen -p -f ~/.ssh/$name, щоб додати її.';
  }

  @override
  String get pfGenerateFailed => 'Не вдалося згенерувати';

  @override
  String get pfAuthentication => 'Автентифікація';

  @override
  String get pfAuthBody =>
      'Віддалені HTTPS використовують системний помічник облікових даних git; віддалені SSH — ваш агент SSH і ключі. Mergelio ніколи не зберігає й не читає ваші паролі чи приватні ключі — тут перелічено лише публічні.';

  @override
  String get pfSshKeys => 'КЛЮЧІ SSH';

  @override
  String get pfGenerateKeyMenu => 'Згенерувати ключ…';

  @override
  String get pfNoSshKeys => 'У ~/.ssh не знайдено ключів SSH';

  @override
  String get pfCopyPublicKey => 'Копіювати публічний ключ';

  @override
  String get pfPublicKeyCopied => 'Публічний ключ скопійовано';

  @override
  String get pfThemeJsonCopied => 'JSON теми скопійовано';

  @override
  String get pfImportTheme => 'Імпортувати тему';

  @override
  String get pfPasteThemeJson => 'Вставте JSON теми';

  @override
  String get pfInvalidThemeJson => 'Некоректний JSON теми';

  @override
  String pfThemeApplied(String name) {
    return 'Застосовано «$name»';
  }

  @override
  String get pfSaveTheme => 'Зберегти тему';

  @override
  String get pfThemeName => 'Назва теми';

  @override
  String pfThemeSaved(String name) {
    return 'Збережено «$name»';
  }

  @override
  String get pfCustomColour => 'Власний колір';

  @override
  String get pfHexHint => 'Hex (напр. #6E7BFF)';

  @override
  String lgCouldNotOpen(String error) {
    return 'Не вдалося відкрити теку журналів: $error';
  }

  @override
  String get lgDiagnosticLogs => 'Діагностичні журнали';

  @override
  String get lgNotActive => 'Запис журналу у файл вимкнено';

  @override
  String get lgReveal => 'Показати';

  @override
  String get pdEmpty =>
      'Профілів ще немає. Додайте один, щоб задати особу для комітів.';

  @override
  String get pdUse => 'Використати';

  @override
  String pdDeleteTitle(String label) {
    return 'Видалити профіль $label?';
  }

  @override
  String get pdDeleteBody =>
      'Профіль буде вилучено. Ключі, на які він посилається у сховищі, залишаться недоторканими.';

  @override
  String get pdAddProfile => 'Додати профіль';

  @override
  String get pfmNew => 'Новий профіль';

  @override
  String get pfmEdit => 'Редагувати профіль';

  @override
  String get pfmProfileName => 'Назва профілю';

  @override
  String get pfmProfileNameHint => 'Робота, Особисте, …';

  @override
  String get pfmDeveloperName => 'Ім’я розробника';

  @override
  String get pfmDeveloperNameHint => 'Ваше ім’я в комітах';

  @override
  String get pfmEmail => 'Email';

  @override
  String get fpTitle => 'Створіть свій перший профіль';

  @override
  String get fpBody =>
      'Кожна група й репозиторій належать до профілю. Перемикання профілів згодом показуватиме лише роботу цього профілю.';

  @override
  String get fpCreateProfile => 'Створити профіль';

  @override
  String get mtCurrent => 'Поточна';

  @override
  String mtCurrentNamed(String into) {
    return 'Поточна — $into';
  }

  @override
  String get mtIncoming => 'Вхідна';

  @override
  String mtIncomingNamed(String branch) {
    return 'Вхідна — $branch';
  }

  @override
  String get mtNeedsReview => '⚠ потребує перевірки';

  @override
  String get mtResolved => '✓ вирішено';

  @override
  String get mtBothAccepted => 'Прийнято обидві ⚠ потребує перевірки';

  @override
  String get mtAcceptBoth => 'Прийняти обидві';

  @override
  String get mtResult => 'РЕЗУЛЬТАТ';

  @override
  String get mtUseEdit => 'Використати редагування';

  @override
  String get mtAccept => 'Прийняти';

  @override
  String get rbPick => 'залишити цей коміт як є';

  @override
  String get rbReword => 'залишити цей коміт, змінити його повідомлення';

  @override
  String get rbSquash =>
      'об’єднати з комітом вище, зберегти обидва повідомлення';

  @override
  String get rbFixup => 'об’єднати з комітом вище, відкинути його повідомлення';

  @override
  String get rbDrop => 'повністю вилучити цей коміт';

  @override
  String get rbPresetAsIs => 'Перемістити коміти як є';

  @override
  String get rbPresetSquashAll => 'Об’єднати в один коміт';

  @override
  String get rbPresetSquashKeepFirst =>
      'Об’єднати, зберегти перше повідомлення';

  @override
  String rbSummaryAsIs(int count) {
    return 'Відтворити всі $count комітів на новій основі. Історія збереже свою форму.';
  }

  @override
  String rbSummarySquashAll(int count) {
    return 'Об’єднати всі $count в один коміт; усі повідомлення буде збережено, одне за одним.';
  }

  @override
  String rbSummarySquashKeepFirst(int count) {
    return 'Об’єднати всі $count в один коміт; збережено буде лише перше повідомлення.';
  }

  @override
  String get rbTitle => 'Інтерактивне перебазування';

  @override
  String rbCommitCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count коміта',
      many: '$count комітів',
      few: '$count коміти',
      one: '$count коміт',
    );
    return '$_temp0';
  }

  @override
  String rbCommitCountOnto(int count, String onto) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count коміта на $onto',
      many: '$count комітів на $onto',
      few: '$count коміти на $onto',
      one: '$count коміт на $onto',
    );
    return '$_temp0';
  }

  @override
  String get rbStart => 'Почати перебазування';

  @override
  String get rbNeedsTwo => 'Потрібно щонайменше 2 коміти.';

  @override
  String get rbCustomize => 'Налаштувати кожен коміт';

  @override
  String get rbCustomizeHint =>
      'Виберіть дію для кожного коміту або перетягніть, щоб змінити порядок.';

  @override
  String get dlgEditCommitMessage => 'Редагувати повідомлення коміту';

  @override
  String dlgUnsavedOne(String path) {
    return '$path має зміни, яких немає на диску.';
  }

  @override
  String get dlgUnsavedMany => 'Ці файли мають зміни, яких немає на диску:';

  @override
  String fteConflictBody(String name) {
    return 'Щось інше записало $name, поки файл був відкритий тут. Збереження замінить ті зміни цим текстом.';
  }

  @override
  String get fteCouldNotOpen => 'Не вдалося відкрити цей файл';

  @override
  String get fteNoResults => 'Немає результатів';

  @override
  String get fteFind => 'Знайти';

  @override
  String get fteReplaceWith => 'Замінити на';

  @override
  String get fteMatchCase => 'Враховувати регістр';

  @override
  String get ftePreviousMatch => 'Попередній збіг';

  @override
  String get fteNextMatch => 'Наступний збіг';

  @override
  String get fteReplaceThis => 'Замінити цей збіг';

  @override
  String get fteReplaceAll => 'Замінити все';

  @override
  String get diffEditingWorkingTree =>
      'Редагування робочого дерева — збережені зміни залишаються непроіндексованими';

  @override
  String get diffStageSelectedLines => 'Проіндексувати вибрані рядки';

  @override
  String get diffUnstageSelectedLines => 'Зняти індексацію з вибраних рядків';

  @override
  String get diffDiscardSelectedLines => 'Відкинути вибрані рядки';

  @override
  String diffUnsavedBody(String path) {
    return 'Введений у $path текст не було записано в робоче дерево.';
  }

  @override
  String get diffUncommittedWorkingTree => 'Незакомічені зміни · робоче дерево';

  @override
  String get diffStageFile => 'Проіндексувати файл';

  @override
  String get diffUnstageFile => 'Зняти індексацію з файлу';

  @override
  String get diffShowChangesOnly => 'Показати лише зміни';

  @override
  String get diffShowWholeFile => 'Показати весь файл';

  @override
  String get diffCouldNotLoad => 'Не вдалося завантажити зміни';

  @override
  String get diffBinaryFile => 'Двійковий файл — зміни не показано';

  @override
  String get diffCouldNotStage => 'Не вдалося проіндексувати';

  @override
  String get diffCouldNotUnstage => 'Не вдалося зняти індексацію';

  @override
  String get diffCouldNotDiscard => 'Не вдалося відкинути';

  @override
  String get diffStageHunk => 'Проіндексувати блок';

  @override
  String get diffUnstageHunk => 'Зняти індексацію з блоку';

  @override
  String get diffDiscardHunk => 'Відкинути блок';

  @override
  String get diffUnstagedLabel => 'Непроіндексовані';

  @override
  String get diffStagedLabel => 'Проіндексовані';

  @override
  String get fepOpenAFile => 'Відкрийте файл, щоб редагувати його';

  @override
  String get fepDeletedOnDisk => 'Видалено з диска — збереження вимкнено';

  @override
  String get pnpNewFileMenu => 'Новий файл…';

  @override
  String get pnpNewFolderMenu => 'Нова тека…';

  @override
  String get pnpRenameMenu => 'Перейменувати…';

  @override
  String get pnpDeleteMenu => 'Видалити…';

  @override
  String get pnpStage => 'Проіндексувати';

  @override
  String get pnpUnstage => 'Зняти індексацію';

  @override
  String get pnpDiscardMenu => 'Відкинути зміни…';

  @override
  String get pnpShowHistory => 'Показати історію';

  @override
  String get pnpRevealInFinder => 'Показати у Finder';

  @override
  String get pnpShowInExplorer => 'Показати в Провіднику';

  @override
  String get pnpOpenContainingFolder => 'Відкрити теку з файлом';

  @override
  String get pnpNewFile => 'Новий файл';

  @override
  String get pnpNewFolder => 'Нова тека';

  @override
  String get pnpDeleteFolderBody =>
      'Теку й увесь її вміст буде вилучено з диска, а не лише з git.';

  @override
  String get pnpDeleteFileBody =>
      'Файл буде вилучено з диска, а не лише з git.';

  @override
  String get pnpDiscardUntrackedBody =>
      'Файл не відстежується, тож відкидання видалить його.';

  @override
  String get pnpDiscardTrackedBody =>
      'Файл повернеться до стану останнього коміту.';

  @override
  String get pnpCouldNotOpenFileManager =>
      'Не вдалося відкрити файловий менеджер';

  @override
  String get pnpOperationFailed => 'Операція не вдалася';

  @override
  String pnpMore(int count) {
    return '…ще $count';
  }

  @override
  String get pnpProject => 'Проєкт';

  @override
  String get pnpShowIgnored => 'Показати ігноровані файли';

  @override
  String get pnpHideIgnored => 'Сховати ігноровані файли';
}
