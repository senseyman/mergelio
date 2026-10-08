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
  String get opPushOptions => 'Відправити…';

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
  String get prefsPullAutostash => 'Автосхов під час стягування';

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
  String get graphLoadingOlder => 'Завантаження давніших комітів…';

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
  String get menuCreateFixup => 'Підготувати fixup для цього коміту';

  @override
  String get menuResetMixed => 'Скинути сюди (--mixed)';

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
  String get menuMarkCompare => 'Позначити для порівняння';

  @override
  String get menuClearCompareMark => 'Зняти позначку порівняння';

  @override
  String menuCompareWith(String ref) {
    return 'Порівняти з $ref';
  }

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
  String get sbReflog => 'Reflog';

  @override
  String get sbNoReflog => 'Немає записів reflog';

  @override
  String get sbCopySha => 'Копіювати SHA';

  @override
  String get sbReflogFailed => 'Не вдалося прочитати reflog';

  @override
  String sbReflogTruncated(int count) {
    return 'Показано перші $count записів';
  }

  @override
  String sbReflogDetachTitle(String sha) {
    return 'Переключитися на $sha?';
  }

  @override
  String get sbReflogDetachBody =>
      'HEAD буде відокремлено на цьому коміті. Жодна гілка не переміщується, тож ви можете будь-коли повернутися до своєї гілки.';

  @override
  String get sbReflogDetach => 'Переключитися';

  @override
  String get sbReflogFilter => 'Фільтрувати записи';

  @override
  String get sbReflogNoMatches => 'Немає відповідних записів';

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
  String get sbCompareWithCurrent => 'Порівняти з поточною';

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
  String bdFastForward(String source, String target) {
    return 'Перемотати «$target» до «$source»';
  }

  @override
  String bdMoveHere(String source, String target) {
    return 'Перемістити «$source» на «$target»';
  }

  @override
  String bdResetSoft(String source, String target) {
    return 'Скинути «$source» до «$target» (--soft)';
  }

  @override
  String bdResetMixed(String source, String target) {
    return 'Скинути «$source» до «$target» (--mixed)';
  }

  @override
  String bdResetHard(String source, String target) {
    return 'Скинути «$source» до «$target» (--hard)';
  }

  @override
  String bdCherryPick(String source, String target) {
    return 'Перенести «$target» на «$source» (cherry-pick)';
  }

  @override
  String bdMergeBody(String source, String target) {
    return 'Перемикає на «$target» і зливає в неї «$source».';
  }

  @override
  String bdRebaseBody(String source, String target) {
    return 'Перемикає на «$source» і переносить її коміти на «$target».';
  }

  @override
  String bdFastForwardBody(String source, String target) {
    return 'Пересуває «$target» вперед до «$source». Новий коміт не створюється.';
  }

  @override
  String bdMoveHereBody(String source, String target) {
    return 'Спрямовує «$source» на «$target» без перемикання. Коміти, що були лише в «$source», можуть стати недосяжними; скасування повертає гілку назад.';
  }

  @override
  String bdResetSoftBody(String source, String target) {
    return 'Пересуває «$source» на «$target». Зміни з покинутих комітів лишаються в індексі.';
  }

  @override
  String bdResetMixedBody(String source, String target) {
    return 'Пересуває «$source» на «$target». Зміни з покинутих комітів лишаються в робочому дереві, не проіндексовані.';
  }

  @override
  String bdResetHardBody(String source, String target) {
    return 'Пересуває «$source» на «$target» і відкидає покинуті коміти. Незакомічені зміни спершу ховаються в stash.';
  }

  @override
  String bdCherryPickBody(String source, String target) {
    return 'Перемикає на «$source» і застосовує коміт «$target» поверх неї.';
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
  String get sbDeleteRemoteTag => 'Видалити тег на віддаленому…';

  @override
  String sbDeleteRemoteTagTitle(String tag, String remote) {
    return 'Видалити тег $tag на $remote?';
  }

  @override
  String get sbDeleteRemoteTagBody =>
      'Тег буде видалено з віддаленого репозиторію. Локальний тег залишиться, і цю дію не можна скасувати.';

  @override
  String get sbCopyName => 'Копіювати назву';

  @override
  String sbCopyNamed(String name) {
    return 'Копіювати «$name»';
  }

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
  String get bbPullFfOnly => 'Стягнути (лише перемотка)';

  @override
  String get bbPullMerge => 'Стягнути (злиття)';

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
  String get ropPushTitle => 'Відправити';

  @override
  String get ropPushRemote => 'Віддалений репозиторій';

  @override
  String get ropPushTags => 'Також відправити всі теги';

  @override
  String get ropPushForce => 'Примусово (with lease)';

  @override
  String get ropPushNoRemotes =>
      'У цьому репозиторії немає віддалених репозиторіїв. Додайте один перед відправленням.';

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
  String get ropSquash => 'Стиснути (проіндексувати, без коміту)';

  @override
  String get ropNoCommit => 'Проіндексувати злиття, без коміту';

  @override
  String get ropFavorLabel => 'Якщо обидві сторони змінили ті самі рядки';

  @override
  String get ropFavorAsk => 'Запитати';

  @override
  String get ropFavorOurs => 'Наші';

  @override
  String get ropFavorTheirs => 'Їхні';

  @override
  String get ropMessageOptional => 'Повідомлення (необов’язково)';

  @override
  String get ropOnlyStaged => 'Лише проіндексовані зміни';

  @override
  String get ropStash => 'Сховати';

  @override
  String ropMainlineRevertTitle(String sha) {
    return 'Відкотити злиття $sha';
  }

  @override
  String ropMainlineCherryPickTitle(String sha) {
    return 'Cherry-pick злиття $sha';
  }

  @override
  String get ropMainlineRevertBody =>
      'Злиття поєднало дві лінії історії, тож git має знати, яку з них залишити. Зміни з іншої гілки буде скасовано.';

  @override
  String get ropMainlineCherryPickBody =>
      'У злиття немає єдиного набору змін для повторення, тож git потрібен батьківський коміт для порівняння. Зміни з іншої гілки буде застосовано.';

  @override
  String ropMainlineParent(int n) {
    return 'Батьківський коміт $n';
  }

  @override
  String get ropMainlineParentFirst => 'гілка, у яку зливали';

  @override
  String get ropMainlineParentOther => 'злита гілка';

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
  String get wtpBreakPausedBody =>
      'Перебазування призупинено на зупинці. Роззирніться, за потреби зробіть коміт чи виправте його, потім продовжте.';

  @override
  String get wtpRewordRejectedBody =>
      'Перебазування призупинено: нове повідомлення коміту відхилено, зазвичай хуком. Виправте повідомлення самостійно або продовжте, щоб залишити старе.';

  @override
  String wtpExecFailedBody(String command) {
    return 'Крок exec `$command` завершився з помилкою. Виправте проблему й закомітьте виправлення, потім продовжте — команда повторно не виконується.';
  }

  @override
  String get wtpShowOutput => 'Показати вивід';

  @override
  String get wtpHideOutput => 'Сховати вивід';

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
  String get wtpTrailers => 'Трейлери';

  @override
  String get wtpSignoff => 'Засвідчити';

  @override
  String get wtpSignoffTip =>
      'Додати трейлер Signed-off-by від імені того, хто робить коміт';

  @override
  String get wtpRefsHint => 'Refs: #12, #34';

  @override
  String get wtpFixesHint => 'Fixes: #12';

  @override
  String get wtpComposerMenu => 'Параметри повідомлення';

  @override
  String get wtpConventional => 'Conventional Commits';

  @override
  String wtpSubjectLimit(int limit) {
    return 'Ліміт заголовка: $limit';
  }

  @override
  String get wtpEditTemplate => 'Шаблон повідомлення…';

  @override
  String wtpWrapDescription(int width) {
    return 'Перенести опис до $width колонок';
  }

  @override
  String get wtpRecentMessages => 'Нещодавні повідомлення';

  @override
  String get wtpNoRecent => 'Нещодавніх повідомлень немає';

  @override
  String get wtpScopeHint => 'область';

  @override
  String get wtpTypeNone => 'без типу';

  @override
  String get wtpBreaking => 'Несумісне';

  @override
  String get wtpBreakingTip => 'Позначає заголовок знаком ! як несумісну зміну';

  @override
  String get wtpTemplateUntouched => 'Спершу відредагуйте шаблон';

  @override
  String get wtpTemplateUntouchedBody =>
      'Повідомлення досі точно збігається з шаблоном.';

  @override
  String get wtpTemplateTitle => 'Шаблон повідомлення';

  @override
  String wtpTemplateBody(String char) {
    return 'Початок кожного нового повідомлення коміту в цьому репозиторії. Рядки, що починаються з $char, — підказки, у коміт вони не потрапляють. Залиште порожнім, щоб використовувати commit.template або .gitmessage з git.';
  }

  @override
  String get wtpTemplateClear => 'Очистити';

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
  String get cmpTitle => 'ПОРІВНЯННЯ';

  @override
  String get cmpSwap => 'Поміняти сторони';

  @override
  String get cmpNoDifferences => 'Немає відмінностей';

  @override
  String get cmpCouldNotRead => 'Не вдалося прочитати порівняння';

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
  String get welGitUnavailable => 'Git не може запуститися';

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
  String gvResetMixedTitle(String sha) {
    return 'Скинути до $sha?';
  }

  @override
  String get gvResetMixedBody =>
      'Переміщує поточну гілку на цей коміт і залишає зміни незакоміченими в робочій копії. Дію можна скасувати.';

  @override
  String get gvResetMixed => 'Reset --mixed';

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
  String get forgePullRequests => 'Пулреквести';

  @override
  String get forgeNoPullRequests => 'Немає відкритих пулреквестів';

  @override
  String get forgeMergeRequests => 'Запити на злиття';

  @override
  String get forgeNoMergeRequests => 'Немає відкритих запитів на злиття';

  @override
  String get forgeIssues => 'Тікети';

  @override
  String get forgeNoIssues => 'Немає відкритих тікетів';

  @override
  String get forgeRefresh => 'Оновити';

  @override
  String get forgeCouldNotOpenPr => 'Не вдалося відкрити пулреквест у браузері';

  @override
  String get forgeCouldNotOpenMr =>
      'Не вдалося відкрити запит на злиття у браузері';

  @override
  String get forgeCouldNotOpenIssue => 'Не вдалося відкрити тікет у браузері';

  @override
  String get forgeConnectHint =>
      'Без токена: без автооновлення, 60 запитів на годину. Підключіть у Налаштуваннях → Облікові дані.';

  @override
  String get forgeConnectHintGitlab =>
      'Без токена: без автооновлення і зі спільним нижчим лімітом запитів. Підключіть у Налаштуваннях → Облікові дані.';

  @override
  String forgeErrUnauthenticated(String forge) {
    return '$forge відхилив збережений токен. Підключіться знову в Налаштуваннях.';
  }

  @override
  String forgeErrRateLimited(String forge, String time) {
    return 'Ліміт запитів $forge вичерпано. Він оновиться о $time.';
  }

  @override
  String forgeErrRateLimitedSoon(String forge) {
    return 'Ліміт запитів $forge вичерпано. Спробуйте трохи пізніше.';
  }

  @override
  String forgeErrNotVisible(String forge) {
    return 'Цей репозиторій недоступний для поточного токена $forge.';
  }

  @override
  String forgeErrOffline(String forge) {
    return 'Не вдалося зʼєднатися з $forge.';
  }

  @override
  String forgeErrServer(String forge, int status) {
    return '$forge відповів помилкою ($status).';
  }

  @override
  String forgeErrMalformed(String forge) {
    return '$forge надіслав відповідь, яку ця версія не змогла прочитати.';
  }

  @override
  String forgeAccountTitle(String forge) {
    return 'Обліковий запис $forge';
  }

  @override
  String get forgeAccountConnected => 'Підключено';

  @override
  String get forgeAccountNotConnected => 'Не підключено';

  @override
  String get forgeTokenLabel => 'Персональний токен доступу';

  @override
  String get forgeConnect => 'Підключити';

  @override
  String get forgeDisconnect => 'Відключити';

  @override
  String forgeTokenRejected(String forge) {
    return '$forge відхилив цей токен.';
  }

  @override
  String forgeTokenSaved(String forge) {
    return 'Підключено до $forge.';
  }

  @override
  String forgeTokenNotKept(String forge) {
    return '$forge прийняв токен, але жодне сховище в цій системі його не зберегло. Налаштуйте credential helper для git і спробуйте ще раз.';
  }

  @override
  String forgeTokenForgotten(String forge) {
    return 'Токен $forge видалено.';
  }

  @override
  String forgeTokenNotForgotten(String forge) {
    return 'Не вдалося видалити токен $forge. Він може залишатися у сховищі облікових даних git.';
  }

  @override
  String get forgeRateBenefit =>
      'Без токена GitHub дозволяє 60 запитів на годину; з токеном — 5000. Відкриття репозиторію коштує близько 23: по одному запиту на кожен список, два на перевірки кожного пулреквеста і один на сам репозиторій.';

  @override
  String get forgeRateBenefitGitlab =>
      'Без токена запити до GitLab використовують спільний нижчий ліміт з усіма іншими анонімними користувачами. Підключення піднімає ліміт до ліміту вашого облікового запису.';

  @override
  String forgeRateRemaining(int remaining, int limit) {
    return 'Залишилось $remaining з $limit запитів цієї години.';
  }

  @override
  String get forgeRefreshInterval =>
      'Інтервал оновлення пулреквестів і запитів на злиття';

  @override
  String lhTitleLine(String path, String line) {
    return '$path · рядок $line';
  }

  @override
  String lhTitleRange(String path, String range) {
    return '$path · рядки $range';
  }

  @override
  String get lhLineHistory => 'Історія рядків';

  @override
  String get lhCouldNotLoad => 'Не вдалося завантажити історію рядків';

  @override
  String get lhNoChanges => 'Жоден коміт не змінював ці рядки';

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
  String get pfScPrevNextConflict => 'Попередній / наступний конфлікт (злиття)';

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
  String get mtKeepMine => 'Залишити мою';

  @override
  String get mtKeepTheirs => 'Залишити вхідну';

  @override
  String get mtDeleteFile => 'Видалити файл';

  @override
  String get mtBinaryConflict =>
      'Двійковий файл — git не може злити його вміст. Залишіть одну версію.';

  @override
  String get mtSubmoduleConflict =>
      'Підмодуль — гілки вказують на різні коміти. Залишіть один.';

  @override
  String get mtDeletedByUs => 'Видалено в цій гілці, змінено у вхідній.';

  @override
  String get mtDeletedByThem => 'Змінено в цій гілці, видалено у вхідній.';

  @override
  String get mtAddedByUs => 'Додано лише в цій гілці.';

  @override
  String get mtAddedByThem => 'Додано лише вхідною гілкою.';

  @override
  String get mtBothDeleted => 'Видалено в обох гілках.';

  @override
  String mtConflictCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count конфлікту',
      many: '$count конфліктів',
      few: '$count конфлікти',
      one: '$count конфлікт',
    );
    return '$_temp0';
  }

  @override
  String mtConflictPosition(int current, int total) {
    return 'Конфлікт $current з $total';
  }

  @override
  String get mtPrevConflict => 'Попередній конфлікт (⌥↑)';

  @override
  String get mtNextConflict => 'Наступний конфлікт (⌥↓)';

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
  String get rbExec =>
      'виконати команду оболонки тут; якщо вона завершиться з помилкою, перебазування призупиниться';

  @override
  String get rbBreak =>
      'зупинитися тут, щоб роззирнутися чи виправити коміт, потім продовжити';

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
  String get rbAutosquash => 'Вбудувати fixup-коміти в їхні цілі';

  @override
  String rbAutosquashHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Знайдено $count коміту fixup!/squash! — кожен переміститься під коміт, який називає.',
      many:
          'Знайдено $count комітів fixup!/squash! — кожен переміститься під коміт, який називає.',
      few:
          'Знайдено $count коміти fixup!/squash! — кожен переміститься під коміт, який називає.',
      one:
          'Знайдено $count коміт fixup!/squash! — він переміститься під коміт, який називає.',
    );
    return '$_temp0';
  }

  @override
  String rbFoldsInto(String target) {
    return '↳ у $target';
  }

  @override
  String get rbUpdateRefs => 'Перемістити й гілки зверху';

  @override
  String rbUpdateRefsHint(String branches) {
    return '$branches вказують на ці коміти й підуть за ними.';
  }

  @override
  String get rbAddExec => 'Додати крок exec';

  @override
  String get rbAddBreak => 'Додати зупинку';

  @override
  String get rbExecFieldHint => 'Команда оболонки, напр. flutter test';

  @override
  String get rbRemoveStep => 'Вилучити крок';

  @override
  String get rbExecConfirmTitle => 'Виконати ці команди?';

  @override
  String rbExecConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Ці команди ($count) виконаються в репозиторії між комітами точно так, як написано. Якщо одна завершиться з помилкою, перебазування там призупиниться.',
      one: 'Ця команда виконається в репозиторії між комітами точно так, як написано. Якщо вона завершиться з помилкою, перебазування там призупиниться.',
    );
    return '$_temp0';
  }

  @override
  String get rbExecConfirmRun => 'Запустити перебазування';

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
  String get diffMoreActions => 'Інші дії';

  @override
  String get diffViewInline => 'Суцільно';

  @override
  String get diffViewSplit => 'Поруч';

  @override
  String get diffCouldNotLoad => 'Не вдалося завантажити зміни';

  @override
  String get lfsBadge => 'LFS';

  @override
  String get lfsBadgeTooltip => 'Зберігається через Git LFS';

  @override
  String get lfsCardModified => 'Об\'єкт LFS';

  @override
  String get lfsCardAdded => 'Додано об\'єкт LFS';

  @override
  String get lfsCardDeleted => 'Видалено об\'єкт LFS';

  @override
  String get lfsCardMovedIn => 'Перенесено в LFS';

  @override
  String get lfsCardMovedOut => 'Винесено з LFS';

  @override
  String get lfsDownloaded => 'Завантажено';

  @override
  String get lfsNotDownloaded => 'Не завантажено';

  @override
  String get lfsToolMissing =>
      'git-lfs не встановлено — файли показано як вказівники';

  @override
  String get lfsMismatch =>
      'Відстежується LFS, але збережено як звичайний blob';

  @override
  String get lfsShowTextDiff => 'Показати текстові зміни';

  @override
  String get lfsBannerText =>
      'Цей репозиторій зберігає файли через Git LFS, але git-lfs не встановлено. Доки ви його не встановите, файли показано як вказівники.';

  @override
  String get lfsBannerDismiss => 'Закрити';

  @override
  String get lfsInstallHomebrew =>
      'Встановіть командою `brew install git-lfs`, потім виконайте `git lfs install`.';

  @override
  String get lfsInstallGitForWindows =>
      'Він входить до Git for Windows — перевстановіть його з позначкою Git LFS, потім виконайте `git lfs install`.';

  @override
  String get lfsInstallPackageManager =>
      'Встановіть git-lfs через менеджер пакетів, потім виконайте `git lfs install`.';

  @override
  String get lfsOpPull => 'Завантажити файли LFS';

  @override
  String get lfsOpFetchAll => 'Отримати всі об\'єкти LFS';

  @override
  String get lfsOpPrune => 'Очистити об\'єкти LFS…';

  @override
  String lfsPointerStrip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлів LFS не завантажено',
      few: '$count файли LFS не завантажено',
      one: '$count файл LFS не завантажено',
    );
    return '$_temp0';
  }

  @override
  String get lfsDownload => 'Завантажити';

  @override
  String get lfsNoRemote =>
      'Немає віддаленого репозиторію, з якого завантажити';

  @override
  String get lfsDownloadUnsafePath =>
      'Цей файл не можна завантажити окремо через його назву — скористайтеся «Завантажити файли LFS».';

  @override
  String get lfsPruneNothing => 'Нічого очищати';

  @override
  String get lfsPruneUnreadable => 'Не вдалося переглянути очищення';

  @override
  String get lfsPruneTitle => 'Очистити об\'єкти LFS';

  @override
  String lfsPruneBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count завантажених об\'єктів LFS?',
      few: 'Видалити $count завантажені об\'єкти LFS?',
      one: 'Видалити $count завантажений об\'єкт LFS?',
    );
    return '$_temp0 Вони не потрібні недавнім комітам і їх можна завантажити знову.';
  }

  @override
  String get lfsPruneConfirm => 'Очистити';

  @override
  String lfsTrackExtension(String pattern) {
    return 'Відстежувати $pattern через LFS';
  }

  @override
  String get lfsTrackFile => 'Відстежувати цей файл через LFS';

  @override
  String get lfsUntrack => 'Припинити відстеження LFS…';

  @override
  String get lfsUntrackTitle => 'Припинити відстеження LFS';

  @override
  String get lfsUntrackBody =>
      'Виберіть шаблон, який прибрати з .gitattributes. Файли, вже збережені в LFS, там і лишаться.';

  @override
  String lfsConvertOffer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count закомічених файлів відповідають шаблону, але не в LFS',
      few: '$count закомічені файли відповідають шаблону, але не в LFS',
      one: '$count закомічений файл відповідає шаблону, але не в LFS',
    );
    return '$_temp0';
  }

  @override
  String get lfsConvertAction => 'Перетворити…';

  @override
  String get lfsConvertTitle => 'Перетворити файли на LFS';

  @override
  String get lfsConvertBody =>
      'Ці файли буде проіндексовано як вказівники LFS разом зі зміною .gitattributes, яка це визначає, і з усіма вашими змінами в них. Нічого не комітиться.';

  @override
  String lfsConvertMore(int count) {
    return 'і ще $count';
  }

  @override
  String get lfsConvertConfirm => 'Проіндексувати як LFS';

  @override
  String get lfsPushHookTitle => 'Хуки LFS не встановлено';

  @override
  String get lfsPushHookBody =>
      'Цей репозиторій зберігає файли через Git LFS, але push звідси надішле лише вказівники — хуки LFS не встановлено.';

  @override
  String get lfsPushInstallAndPush => 'Встановити хуки LFS і надіслати';

  @override
  String get lfsPushHookNotRunnable =>
      'Хук pre-push існує, але git не запустить його, бо файл не виконуваний. Нічого не надіслано.';

  @override
  String get lfsLockChipYou => 'Ви';

  @override
  String lfsLockTooltip(String owner, String age) {
    return 'Заблоковано: $owner · $age';
  }

  @override
  String get lfsLockFile => 'Заблокувати файл';

  @override
  String get lfsUnlockFile => 'Розблокувати файл';

  @override
  String get lfsForceUnlock => 'Примусово розблокувати…';

  @override
  String get lfsForceUnlockTitle => 'Зняти чуже блокування';

  @override
  String lfsForceUnlockBody(String owner, String age) {
    return 'Файл заблоковано користувачем $owner ($age). Зняття блокування не завадить надіслати їхні зміни, і їхня робота може бути втрачена.';
  }

  @override
  String get lfsForceUnlockConfirm => 'Зняти блокування';

  @override
  String get lfsLocksSection => 'Блокування';

  @override
  String get lfsLocksYours => 'Ваші';

  @override
  String get lfsLocksOthers => 'Інші';

  @override
  String get lfsLocksRefresh => 'Оновити';

  @override
  String get lfsLocksStale =>
      'Не вдалося оновити блокування — показано останній відомий список';

  @override
  String lfsLocksMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'і ще $count',
      many: 'і ще $count',
      few: 'і ще $count',
      one: 'і ще $count',
    );
    return '$_temp0';
  }

  @override
  String lfsLocksMoreAtLeast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'і ще $count+',
      many: 'і ще $count+',
      few: 'і ще $count+',
      one: 'і ще $count+',
    );
    return '$_temp0';
  }

  @override
  String lfsLockTooltipNoAge(String owner) {
    return 'Заблоковано: $owner';
  }

  @override
  String lfsForceUnlockBodyNoAge(String owner) {
    return 'Файл заблоковано користувачем $owner. Зняття блокування не завадить надіслати їхні зміни, і їхня робота може бути втрачена.';
  }

  @override
  String lfsLocksRefreshedAt(String age) {
    return 'Останнє оновлення: $age';
  }

  @override
  String get lfsLocksUnsupported =>
      'Сервер цього репозиторію не підтримує блокування файлів.';

  @override
  String get lfsPushLockedTitle => 'Файли, заблоковані іншими';

  @override
  String get lfsPushLockedBody =>
      'Ці файли заблокували інші. Надсилання змін до них може перезаписати чужу роботу.';

  @override
  String get lfsPushAnyway => 'Однаково надіслати';

  @override
  String get lfsPushToolTitle => 'git-lfs не встановлено';

  @override
  String get lfsPushToolBody =>
      'Цей репозиторій зберігає файли через Git LFS. Push без git-lfs надсилає вказівники без вмісту.';

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

  @override
  String get prefsTabUpdates => 'Оновлення';

  @override
  String updateBannerAvailable(String version) {
    return 'Доступна Mergelio $version';
  }

  @override
  String get updateBannerDownloading => 'Завантаження оновлення…';

  @override
  String get updateBannerReady => 'Оновлення готове до встановлення';

  @override
  String get updateActionDownload => 'Завантажити';

  @override
  String get updateActionInstall => 'Встановити й перезапустити';

  @override
  String get updateActionNotes => 'Опис змін';

  @override
  String get updateActionSkip => 'Пропустити цю версію';

  @override
  String get updateActionLater => 'Пізніше';

  @override
  String get updateBlockedBusy => 'Чекаємо, поки завершиться поточна операція';

  @override
  String get updateManualNone => 'У вас найновіша версія';

  @override
  String get updateManualFailed => 'Не вдалося перевірити оновлення';

  @override
  String get updateLinuxHint => 'Встановіть через менеджер пакетів';

  @override
  String get updateConsentTitle => 'Перевіряти оновлення?';

  @override
  String get updateConsentBody =>
      'Mergelio може раз на добу питати GitHub про новий реліз. Без акаунта, без ідентифікаторів, нічого про ваші репозиторії не надсилається.';

  @override
  String get updateConsentYes => 'Перевіряти';

  @override
  String get updateConsentNo => 'Не перевіряти';

  @override
  String updatePrefsCurrent(String version) {
    return 'Поточна версія: $version';
  }

  @override
  String get updatePrefsAuto => 'Перевіряти оновлення автоматично';

  @override
  String get updatePrefsCheckNow => 'Перевірити зараз';

  @override
  String updatePrefsLastCheck(String when) {
    return 'Остання перевірка: $when';
  }

  @override
  String get updatePrefsNever => 'ніколи';

  @override
  String get askpassTitle => 'Потрібна автентифікація';

  @override
  String get askpassFallback => 'Введіть облікові дані';

  @override
  String get askpassSubmit => 'OK';

  @override
  String get askpassYes => 'Так';

  @override
  String get askpassNo => 'Ні';

  @override
  String get forgeAgoNow => 'зараз';

  @override
  String forgeAgoMinutes(int n) {
    return '$nхв';
  }

  @override
  String forgeAgoHours(int n) {
    return '$nгод';
  }

  @override
  String forgeAgoDays(int n) {
    return '$nд';
  }

  @override
  String get bisectAwaitingGood =>
      'Бісекція триває. Позначте коміт, який точно робочий.';

  @override
  String bisectRevisionsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'залишилося $count коміта',
      many: 'залишилося $count комітів',
      few: 'залишилося $count коміти',
      one: 'залишився $count коміт',
    );
    return '$_temp0';
  }

  @override
  String bisectStepsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'приблизно $count кроку',
      many: 'приблизно $count кроків',
      few: 'приблизно $count кроки',
      one: 'приблизно $count крок',
    );
    return '$_temp0';
  }

  @override
  String bisectTesting(String sha) {
    return 'Перевіряємо $sha';
  }

  @override
  String get bisectGood => 'Робочий';

  @override
  String get bisectBad => 'Зламаний';

  @override
  String get bisectSkip => 'Пропустити';

  @override
  String get bisectReset => 'Скинути бісекцію';

  @override
  String get bisectLog => 'Журнал';

  @override
  String get bisectLogFailed => 'Не вдалося прочитати журнал бісекції.';

  @override
  String get bisectLogEmpty => 'Рішень ще не записано.';

  @override
  String get bisectFirstBadTitle => 'Перший зламаний коміт';

  @override
  String get bisectJumpToCommit => 'Перейти до коміта';

  @override
  String get bisectCopySha => 'Копіювати SHA';

  @override
  String get bisectCopyFixup => 'Копіювати fixup!';

  @override
  String get bisectRevertCommit => 'Відкотити цей коміт';

  @override
  String get bisectRevertNotLoaded =>
      'Цей коміт поза завантаженою історією. Прогорніть граф, щоб завантажити його, і відкотіть із його рядка.';

  @override
  String get bisectPillGood => 'робочий';

  @override
  String get bisectPillBad => 'зламаний';

  @override
  String get bisectPillSkip => 'пропущено';

  @override
  String get bisectMenuStart => 'Почати бісекцію звідси';

  @override
  String get bisectMenuGood => 'Позначити як робочий';

  @override
  String get bisectMenuBad => 'Позначити як зламаний';

  @override
  String get bisectMenuSkip => 'Пропустити цей коміт';

  @override
  String get bisectQuitTitle => 'Бісекція триває';

  @override
  String get bisectQuitBody =>
      'Вихід або закриття репозиторію залишить його у стані detached HEAD. Спочатку скинути бісекцію?';

  @override
  String get bisectQuitAnyway => 'Все одно продовжити';

  @override
  String get bisectNoMarks =>
      'Бісекція триває. Позначте зламаний коміт, щоб почати.';

  @override
  String get bisectUnreadable => 'Не вдалося прочитати стан бісекції';

  @override
  String get bisectRun => 'Запустити команду…';

  @override
  String get bisectRunTitle => 'Запустити команду для бісекції';

  @override
  String get bisectRunHint => 'Команда для тестування кожного коміта';

  @override
  String get bisectRunWillExecute => 'Буде виконано:';

  @override
  String get bisectRunTreeWarning =>
      'Команда, яка змінює відслідковувані файли, зламає запуск.';

  @override
  String get bisectRunStart => 'Запустити';

  @override
  String bisectRunning(String command) {
    return 'Виконання $command';
  }

  @override
  String get bisectRunExhausted =>
      'Усі коміти, що залишилися, пропущено, тому git не може звузити пошук.';

  @override
  String get bisectRunUnrunnable =>
      'Вашу команду не можна запустити. Переконайтеся, що вона існує та є виконуваною.';

  @override
  String get bisectRunTreeDirtied =>
      'Ваша команда змінила відслідковувані файли, тому git не зміг переключитися на наступний коміт.';

  @override
  String get bisectRunCancelled =>
      'Запуск скасовано. Записані рішення збережені.';

  @override
  String get mntTitle => 'Обслуговування репозиторію';

  @override
  String get mntPaletteOpen => 'Обслуговування репозиторію…';

  @override
  String get mntStorage => 'Сховище';

  @override
  String mntStorageTotal(String size) {
    return 'Дані git: $size';
  }

  @override
  String get mntPacks => 'Пакети';

  @override
  String mntPackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count пакетів',
      few: '$count пакети',
      one: '$count пакет',
    );
    return '$_temp0';
  }

  @override
  String get mntLoose => 'Окремі об\'єкти';

  @override
  String mntLooseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count об\'єктів',
      few: '$count об\'єкти',
      one: '$count об\'єкт',
    );
    return '$_temp0';
  }

  @override
  String get mntLfs => 'Об\'єкти LFS';

  @override
  String get mntOther => 'Інші дані git';

  @override
  String get mntStorageNote => 'Файли робочого дерева не враховуються.';

  @override
  String mntReadFailed(String error) {
    return 'Не вдалося прочитати: $error';
  }

  @override
  String get mntBlobs => 'Найбільші файли в історії';

  @override
  String get mntBlobsIntro =>
      'Переглядає кожен об\'єкт в історії репозиторію. На великому репозиторії це може тривати кілька хвилин.';

  @override
  String get mntScan => 'Сканувати';

  @override
  String get mntRescan => 'Сканувати знову';

  @override
  String get mntScanning => 'Сканування історії…';

  @override
  String mntScannedAt(String when) {
    return 'Скановано $when';
  }

  @override
  String get mntScanStale =>
      'Застаріло: гілки або теги змінилися після сканування';

  @override
  String mntScanFailed(String error) {
    return 'Сканування не вдалося: $error';
  }

  @override
  String get mntNoBlobs => 'В історії немає файлів.';

  @override
  String get mntNoPath => '(без шляху)';

  @override
  String get mntNoCommit => 'немає в історії жодної гілки чи тегу';

  @override
  String get mntBranches => 'Гілки';

  @override
  String mntMergedInto(String trunk, int days) {
    return 'Злиті в $trunk, або без змін понад $days дн., або їхня віддалена гілка зникла.';
  }

  @override
  String get mntNoBranches => 'Немає злитих чи застарілих гілок.';

  @override
  String get mntTagMerged => 'злита';

  @override
  String get mntTagStale => 'застаріла';

  @override
  String get mntTagGone => 'віддалена гілка зникла';

  @override
  String mntHeldBy(String path) {
    return 'відкрита в $path';
  }

  @override
  String get mntSelectAll => 'Вибрати всі';

  @override
  String mntDeleteSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count гілок',
      few: 'Видалити $count гілки',
      one: 'Видалити $count гілку',
    );
    return '$_temp0';
  }

  @override
  String get mntDeleteTitle => 'Видалення гілок';

  @override
  String mntDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count гілок?',
      few: 'Видалити $count гілки?',
      one: 'Видалити $count гілку?',
    );
    return '$_temp0 Скасування поверне їх.';
  }

  @override
  String get mntDeleteForce =>
      'Ці гілки не злиті й будуть видалені примусово. Їхні коміти залишаться доступними лише через reflog:';

  @override
  String get mntDeleteConfirm => 'Видалити';

  @override
  String get mntWorktrees => 'Робочі дерева';

  @override
  String mntPrunable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count робочих дерев вказують на відсутні каталоги',
      few: '$count робочі дерева вказують на відсутні каталоги',
      one: '$count робоче дерево вказує на відсутній каталог',
    );
    return '$_temp0';
  }

  @override
  String get mntNoPrunable => 'Нічого очищати.';

  @override
  String get mntPrune => 'Очистити…';

  @override
  String get mntReflog => 'Reflog';

  @override
  String mntReflogExpiry(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Наступний gc видалить $count записів reflog.',
      few: 'Наступний gc видалить $count записи reflog.',
      one: 'Наступний gc видалить $count запис reflog.',
      zero: 'Наступний gc не видалить жодного запису reflog.',
    );
    return '$_temp0';
  }

  @override
  String get mntHousekeeping => 'Прибирання';

  @override
  String get mntHousekeepingHint =>
      'Перепаковує об\'єкти й видаляє недосяжні, які git вважає застарілими. Mergelio ніколи не запускає це сам.';

  @override
  String get mntRunGc => 'Запустити gc';

  @override
  String get mntRunMaintenance => 'Запустити maintenance';

  @override
  String get mntGcTitle => 'Запустити git gc?';

  @override
  String get mntGcBody =>
      'git gc перепаковує репозиторій і видаляє недосяжні об\'єкти, старші за налаштований термін. Це може тривати довго; скасувати можна з рядка стану.';

  @override
  String get mntMaintenanceTitle => 'Запустити git maintenance?';

  @override
  String get mntMaintenanceBody =>
      'Виконує завдання обслуговування, увімкнені в налаштуваннях репозиторію (gc, якщо жодне не задано). Це може тривати довго; скасувати можна з рядка стану.';

  @override
  String get mntRun => 'Запустити';

  @override
  String mntSizeChange(String before, String after) {
    return 'Дані git: $before → $after';
  }

  @override
  String mntHeldByPrunable(String path) {
    return 'відкрита в $path, якого вже немає. Спершу очистіть робочі дерева.';
  }

  @override
  String get mntShowCommit => 'Показати цей коміт у графі';

  @override
  String get bdSideBySide => 'Поруч';

  @override
  String get bdSwipe => 'Шторка';

  @override
  String get bdOnionSkin => 'Накладання';

  @override
  String get bdDifference => 'Різниця';

  @override
  String get bdBefore => 'До';

  @override
  String get bdAfter => 'Після';

  @override
  String get bdTooLarge => 'Завеликий для перегляду';

  @override
  String get bdUnavailable => 'Перегляд недоступний';

  @override
  String get bdNothingToShow => 'Немає вмісту з жодного боку';

  @override
  String bdHexPreview(int count) {
    return 'Перші $count байтів';
  }

  @override
  String get stTitle => 'СХОВАНКА';

  @override
  String stBase(String sha) {
    return 'Створено на $sha';
  }

  @override
  String get stUntrackedFiles => 'НЕВІДСТЕЖУВАНІ ФАЙЛИ';

  @override
  String get stNoChanges => 'Ця схованка не містить змін';

  @override
  String get stCouldNotRead => 'Не вдалося прочитати схованку';

  @override
  String get stRename => 'Перейменувати';

  @override
  String get stRenameMenu => 'Перейменувати…';

  @override
  String stRenameTitle(String ref) {
    return 'Перейменувати $ref';
  }

  @override
  String get stRenameLabel => 'Повідомлення';

  @override
  String get stBranch => 'Гілка…';

  @override
  String get stBranchMenu => 'Гілка зі схованки…';

  @override
  String stBranchTitle(String ref) {
    return 'Гілка з $ref';
  }

  @override
  String get stBranchLabel => 'Назва нової гілки';

  @override
  String get stBranchConfirm => 'Створити гілку';

  @override
  String get stApplyFile => 'Застосувати до робочого дерева';

  @override
  String get stApplyHunk => 'Застосувати блок';

  @override
  String get ropKeepIndex => 'Залишити проіндексовані зміни на місці';

  @override
  String get ropIncludeUntracked => 'Включити невідстежувані файли';

  @override
  String get ropStashFiles => 'Файли для схову';

  @override
  String get ropNothingToStash => 'Нічого ховати';

  @override
  String get rvTitle => 'ПЕРЕГЛЯД';

  @override
  String get rvPickTitle => 'Перегляд гілок';

  @override
  String get rvBase => 'База';

  @override
  String get rvHead => 'Гілка змін';

  @override
  String get rvSideHint => 'Гілка, тег, віддалена гілка або коміт';

  @override
  String get rvWorktreeNote =>
      'Робоче дерево береться за останнім комітом; його незакомічені зміни до перегляду не входять.';

  @override
  String rvNotACommit(String ref) {
    return '«$ref» — не коміт у цьому репозиторії';
  }

  @override
  String get rvOpen => 'Відкрити перегляд';

  @override
  String get rvSwap => 'Поміняти базу й гілку змін';

  @override
  String get rvModeThreeDot => 'Від розгалуження';

  @override
  String get rvModeTwoDot => 'Між вершинами';

  @override
  String rvThreeDotCaption(String range, String head, String base) {
    return '$range: що змінила $head від відгалуження з $base, як у пул-реквесті.';
  }

  @override
  String rvTwoDotCaption(String range, String base, String head) {
    return '$range: усі відмінності між вершинами $base і $head, зокрема зміни, зроблені лише в $base.';
  }

  @override
  String rvAheadBehind(String head, int ahead, int behind, String base) {
    return '$head: попереду на $ahead, позаду на $behind відносно $base';
  }

  @override
  String rvFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлу',
      many: '$count файлів',
      few: '$count файли',
      one: '$count файл',
    );
    return '$_temp0';
  }

  @override
  String rvViewedCount(int viewed, int total) {
    return 'переглянуто $viewed з $total';
  }

  @override
  String get rvViewed => 'Переглянуто';

  @override
  String rvCommits(int count) {
    return 'КОМІТИ ($count)';
  }

  @override
  String rvCommitsTruncated(int count) {
    return 'Показано $count найновіших';
  }

  @override
  String get rvNoCommits => 'У гілці змін немає комітів, яких бракує базі';

  @override
  String get rvFiles => 'ФАЙЛИ';

  @override
  String rvNoMergeBase(String base, String head) {
    return '$base і $head не мають спільної історії, тож точки розгалуження немає. Режим «Між вершинами» все одно покаже відмінності.';
  }

  @override
  String get rvUseTwoDot => 'Показати між вершинами';

  @override
  String get rvNoChanges => 'Змін у файлах немає';

  @override
  String get rvCouldNotRead => 'Не вдалося прочитати перегляд';

  @override
  String get rvCouldNotReadFile => 'Не вдалося прочитати зміни цього файлу';

  @override
  String get rvCollapseAll => 'Згорнути все';

  @override
  String get rvExpandAll => 'Розгорнути все';

  @override
  String rvLargeDiff(int count) {
    return 'Великий diff ($count рядків). Розгорніть, щоб показати.';
  }

  @override
  String get rvBinary =>
      'Двійковий або LFS-файл. Відкрийте його в переглядачі змін, щоб порівняти.';

  @override
  String get rvNoContentChange => 'Перейменовано без змін вмісту';

  @override
  String get rvOpenInDiff => 'Відкрити в переглядачі змін';

  @override
  String get rvFileHistoryAtHead => 'Історія файлу в гілці змін';

  @override
  String get rvBlameAtHead => 'Авторство в гілці змін';

  @override
  String get rvExport => 'Експорт patch-файлів';

  @override
  String get rvSavePatches => 'Зберегти як patch-файли…';

  @override
  String get rvCopyPatch => 'Копіювати як patch';

  @override
  String rvPatchesSaved(int count, String dir) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Збережено $count patch-файлу у $dir',
      many: 'Збережено $count patch-файлів у $dir',
      few: 'Збережено $count patch-файли у $dir',
      one: 'Збережено $count patch-файл у $dir',
    );
    return '$_temp0';
  }

  @override
  String get rvPatchCopied => 'Patch скопійовано';

  @override
  String get rvExportFailed => 'Не вдалося експортувати patch-файли';

  @override
  String get rvOpenPr => 'Відкрити пул-реквест';

  @override
  String get rvOpenMr => 'Відкрити мерж-реквест';

  @override
  String get rvKindBranch => 'гілка';

  @override
  String get rvKindRemote => 'віддалена';

  @override
  String get rvKindTag => 'тег';

  @override
  String get rvKindWorktree => 'робоче дерево';

  @override
  String get rvReviewAgainstCurrent => 'Переглянути відносно поточної';

  @override
  String get rvPaletteReview => 'Перегляд гілок…';

  @override
  String rvNoOpenPr(String branch) {
    return 'Немає єдиного відкритого пул-реквесту для $branch';
  }

  @override
  String rvNoOpenMr(String branch) {
    return 'Немає єдиного відкритого мерж-реквесту для $branch';
  }

  @override
  String get rvPrLookupFailed => 'Не вдалося знайти пул-реквест';

  @override
  String get rvMrLookupFailed => 'Не вдалося знайти мерж-реквест';

  @override
  String get sigGood => 'Перевірений підпис';

  @override
  String get sigUntrusted => 'Дійсний, ключ без довіри';

  @override
  String get sigExpired => 'Прострочений підпис';

  @override
  String get sigExpiredKey => 'Прострочений ключ';

  @override
  String get sigRevoked => 'Відкликаний ключ';

  @override
  String get sigBad => 'Недійсний підпис';

  @override
  String get sigUnverifiable => 'Не вдалося перевірити підпис';

  @override
  String get sigNone => 'Без підпису';

  @override
  String get sigShowDetails => 'Показати деталі підпису';

  @override
  String get sigHideDetails => 'Сховати деталі підпису';

  @override
  String get sigSigner => 'Підписант';

  @override
  String get sigKey => 'Ключ';

  @override
  String get sigFingerprint => 'Відбиток';

  @override
  String get sigPrimaryKey => 'Основний ключ';

  @override
  String get sigTrust => 'Довіра';

  @override
  String get sigFormat => 'Формат';

  @override
  String get sigUnknownSigner => 'Невідомий підписант';

  @override
  String get sigHintNoAllowedSigners =>
      'Підпис відповідає ключу, але git називає SSH-підписанта лише тоді, коли задано gpg.ssh.allowedSignersFile.';

  @override
  String sigHintKeyNotAllowed(String path) {
    return 'Цього SSH-ключа немає у файлі дозволених підписантів ($path).';
  }

  @override
  String get sigHintMissingKey =>
      'Публічного ключа підписанта немає на цьому комп\'ютері, тож підпис не вдалося перевірити.';

  @override
  String sigTag(String name) {
    return 'Тег $name';
  }

  @override
  String get sigPaletteAudit => 'Перевірити підписи…';

  @override
  String get sigAuditTitle => 'Перевірка підписів';

  @override
  String get sigAuditBase => 'Від';

  @override
  String get sigAuditBaseHint => 'гілка, тег або коміт';

  @override
  String get sigAuditRun => 'Перевірити';

  @override
  String sigAuditRange(String range) {
    return 'Перевіряє $range: коміти, досяжні з HEAD, але не з бази.';
  }

  @override
  String sigAuditAllVerified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Усі $count комітів мають перевірений підпис',
      few: 'Усі $count коміти мають перевірений підпис',
      one: '$count коміт має перевірений підпис',
    );
    return '$_temp0';
  }

  @override
  String sigAuditSummary(int count, int unverified) {
    String _temp0 = intl.Intl.pluralLogic(
      unverified,
      locale: localeName,
      other: '$unverified комітів із $count не мають перевіреного підпису',
      few: '$unverified коміти з $count не мають перевіреного підпису',
      one: '$unverified коміт із $count не має перевіреного підпису',
    );
    return '$_temp0';
  }

  @override
  String get sigAuditEmpty => 'У цьому діапазоні немає комітів';

  @override
  String sigAuditTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перевірено лише останні $count комітів.',
      few: 'Перевірено лише останні $count коміти.',
      one: 'Перевірено лише останній $count коміт.',
    );
    return '$_temp0';
  }

  @override
  String get sigAuditFailed => 'Не вдалося перевірити підписи';

  @override
  String sigHintSignersUnreadable(String path) {
    return 'Не вдалося відкрити файл дозволених підписантів ($path), тож git не може назвати підписанта.';
  }

  @override
  String sigHintVerifierMissing(String program) {
    return 'git не зміг запустити $program, тож нічого не перевірено. Встановіть його або вкажіть шлях для git (gpg.program, gpg.ssh.program).';
  }

  @override
  String sigMoreTags(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перевірити ще $count тегів',
      few: 'Перевірити ще $count теги',
      one: 'Перевірити ще $count тег',
    );
    return '$_temp0';
  }

  @override
  String get sigHintSshUnconfigured =>
      'git перевіряє SSH-підписи лише тоді, коли gpg.ssh.allowedSignersFile вказує на файл дозволених підписантів. Задайте його, щоб перевіряти коміти з SSH-підписом.';

  @override
  String get hkTitle => 'Git-хуки';

  @override
  String get hkPaletteOpen => 'Git-хуки…';

  @override
  String get hkDir => 'Каталог хуків';

  @override
  String hkCustomPath(String path) {
    return 'Задано через core.hooksPath: $path';
  }

  @override
  String hkManaged(String tool) {
    return 'Керується $tool — він може перезаписати зміни, зроблені тут, коли перевстановить свої хуки.';
  }

  @override
  String get hkEmpty => 'У цьому репозиторії немає хуків.';

  @override
  String get hkStateActive => 'Активний';

  @override
  String get hkStateDisabled => 'Вимкнений';

  @override
  String get hkStateSample => 'Зразок';

  @override
  String get hkEdit => 'Редагувати';

  @override
  String get hkUseSample => 'Використати зразок';

  @override
  String get hkEnable => 'Увімкнути — git запускатиме цей хук';

  @override
  String get hkDisable => 'Вимкнути — git пропускатиме цей хук';

  @override
  String hkEditorTitle(String hook) {
    return 'Редагування хука $hook';
  }

  @override
  String get hkSkipHooks => 'Без хуків';

  @override
  String get hkSkipArmed => 'Наступний коміт пропустить хуки (--no-verify)';

  @override
  String get hkSkipDisarm => 'Знову запускати хуки';

  @override
  String hkRejectedTitle(String hook) {
    return 'Хук $hook відхилив коміт';
  }

  @override
  String hkOutputFrom(String hook) {
    return 'Вивід $hook';
  }

  @override
  String get hkNoOutput => 'Хук нічого не вивів.';

  @override
  String get hkMessageKept => 'Ваше повідомлення збережено.';

  @override
  String get hkManage => 'Керувати хуками…';

  @override
  String get hkSkipNext => 'Пропустити хуки для наступного коміту';

  @override
  String get hkLinkedNoToggle =>
      'Посилання на файл в іншому місці — змінюйте його режим там, щоб зміна не відбувалася непомітно.';

  @override
  String hkChangeFailed(String hook) {
    return 'Не вдалося змінити хук $hook';
  }

  @override
  String get hkFailNotFound => 'Файлу хука більше немає.';

  @override
  String get hkFailExists => 'Хук із такою назвою вже існує.';

  @override
  String get hkFailOutside =>
      'Хук посилається на файл поза репозиторієм, тож звідси його не змінено.';

  @override
  String get hkFailLinked =>
      'Хук посилається на файл в іншому місці; змініть режим того файлу.';

  @override
  String get hkRewordSkip => 'Змінити без хуків';

  @override
  String get dashTitle => 'Панель';

  @override
  String get dashToolbarTooltip =>
      'Усі репозиторії цієї групи з першого погляду (⌘⇧D)';

  @override
  String dashRepoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count репозиторію',
      many: '$count репозиторіїв',
      few: '$count репозиторії',
      one: '$count репозиторій',
    );
    return '$_temp0';
  }

  @override
  String get dashFetchAll => 'Отримати все';

  @override
  String get dashFetchAllTooltip =>
      'Виконати fetch для кожного репозиторію групи, по кілька одночасно';

  @override
  String get dashPullAll => 'Pull із перемотуванням';

  @override
  String get dashPullAllTooltip =>
      'Перемотати вперед кожну чисту гілку, яка лише відстає від upstream. Нічого не зливається й не комітиться; решту перелічено з причиною.';

  @override
  String get dashRefresh => 'Оновити';

  @override
  String get dashEmpty => 'У цій групі немає репозиторіїв.';

  @override
  String get dashDetached => 'відʼєднаний HEAD';

  @override
  String get dashUnborn => 'ще немає комітів';

  @override
  String get dashNoUpstream => 'без upstream';

  @override
  String get dashUpstreamGone => 'upstream зник';

  @override
  String dashUpstreamGoneTooltip(String upstream) {
    return '$upstream більше не існує на віддаленому репозиторії';
  }

  @override
  String dashAheadBehindTooltip(int ahead, int behind, String upstream) {
    return 'попереду на $ahead, позаду на $behind відносно $upstream';
  }

  @override
  String dashChanged(int count) {
    return 'змінено: $count';
  }

  @override
  String dashConflicted(int count) {
    return 'конфліктів: $count';
  }

  @override
  String dashUntracked(int count) {
    return 'невідстежуваних: $count';
  }

  @override
  String dashStashes(int count) {
    return 'у схованці: $count';
  }

  @override
  String get dashClean => 'чисто';

  @override
  String dashFetchedAgo(String age) {
    return 'fetch $age';
  }

  @override
  String get dashNeverFetched => 'fetch ще не виконувався';

  @override
  String get dashUnreadable => 'Не вдалося прочитати цей репозиторій';

  @override
  String get dashOpMerge => 'злиття';

  @override
  String get dashOpRebase => 'rebase';

  @override
  String get dashOpAm => 'застосування патчів';

  @override
  String get dashOpCherryPick => 'cherry-pick';

  @override
  String get dashOpRevert => 'скасування коміту';

  @override
  String get dashOpBisect => 'bisect';

  @override
  String get dashRunQueued => 'у черзі';

  @override
  String get dashRunFetched => 'отримано';

  @override
  String get dashRunPulled => 'оновлено';

  @override
  String get dashRunFailed => 'помилка';

  @override
  String get dashRunCancelled => 'скасовано';

  @override
  String get dashSkipNoRemote => 'пропущено: немає віддаленого репозиторію';

  @override
  String get dashSkipUnreadable => 'пропущено: не вдалося прочитати';

  @override
  String get dashSkipOperation => 'пропущено: триває операція';

  @override
  String get dashSkipDetached => 'пропущено: відʼєднаний HEAD';

  @override
  String get dashSkipNoUpstream => 'пропущено: без upstream';

  @override
  String get dashSkipUpstreamGone => 'пропущено: upstream зник';

  @override
  String get dashSkipDirty => 'пропущено: незакомічені зміни';

  @override
  String get dashSkipDiverged =>
      'пропущено: гілки розійшлися, потрібне злиття або rebase';

  @override
  String get dashSkipUpToDate => 'пропущено: актуально';

  @override
  String get dashFetchBusy => 'Fetch усіх репозиторіїв';

  @override
  String get dashPullBusy => 'Pull репозиторіїв із перемотуванням';

  @override
  String get dashFetchDone => 'Fetch усіх завершено';

  @override
  String get dashPullDone => 'Pull завершено';

  @override
  String dashBatchSummary(int done, int failed, int skipped, int cancelled) {
    return 'успішно: $done, помилок: $failed, пропущено: $skipped, скасовано: $cancelled';
  }

  @override
  String get dashPaletteOpen => 'Відкрити панель';

  @override
  String dashPaletteGoTo(String name) {
    return 'Перейти до $name';
  }
}
