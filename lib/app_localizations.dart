import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'language_catalog.dart';
import 'help_catalog.dart';
import 'mobile_catalog.dart';
import 'server_error_catalog.dart';
import 'settings_catalog.dart';
import 'conversation_catalog.dart';
import 'approval_catalog.dart';
import 'drawer_catalog.dart';

enum AppLanguage {
  zh('简体中文', 'zh', 'CN'),
  zhHant('繁體中文', 'zh', 'TW'),
  en('English', 'en'),
  ja('日本語', 'ja'),
  ko('한국어', 'ko'),
  es('Español', 'es'),
  fr('Français', 'fr'),
  de('Deutsch', 'de'),
  pt('Português', 'pt'),
  ru('Русский', 'ru'),
  ar('العربية', 'ar'),
  hi('हिन्दी', 'hi'),
  id('Bahasa Indonesia', 'id'),
  vi('Tiếng Việt', 'vi');

  const AppLanguage(this.nativeName, this.code, [this.country]);
  final String nativeName;
  final String code;
  final String? country;
  Locale get locale => Locale(code, country);
  TextDirection get direction =>
      this == ar ? TextDirection.rtl : TextDirection.ltr;
  static AppLanguage fromSaved(String saved) =>
      AppLanguage.values
          .where((language) => language.name == saved)
          .firstOrNull ??
      zh;
}

class LanguagePreference extends ValueNotifier<AppLanguage> {
  LanguagePreference() : super(AppLanguage.zh);
  static const channel = MethodChannel('com.agenttower.mobile/credentials');
  Future<void> _writes = Future.value();
  int _revision = 0;
  bool _disposed = false;
  Future<void> load() async {
    final revision = _revision;
    try {
      final saved = await channel.invokeMethod<String>('readLanguage');
      if (!_disposed && _revision == revision && saved != null) {
        value = AppLanguage.fromSaved(saved);
      }
    } on MissingPluginException {
      // Embedded previews can run without native preferences.
    } on PlatformException {
      // Keep the default when storage is temporarily unavailable.
    }
  }

  Future<void> select(AppLanguage language) {
    _revision++;
    value = language;
    _writes = _writes
        .catchError((Object _) {})
        .then(
          (_) => channel.invokeMethod<void>('writeLanguage', language.name),
        );
    return _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Future<void> showLanguagePicker(BuildContext context) async {
  final locale = AppLocale.maybeOf(context);
  if (locale?.onChanged == null) return;
  final selected = await showModalBottomSheet<AppLanguage>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                AppStrings(locale!.language).languageLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final language in AppLanguage.values)
                    ListTile(
                      key: ValueKey('language-${language.name}'),
                      title: Text(
                        language.nativeName,
                        textDirection: language.direction,
                      ),
                      trailing: locale.language == language
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, language),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (selected != null && context.mounted) locale!.onChanged!(selected);
}

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});
  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.maybeOf(context);
    if (locale?.onChanged == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('language-switch'),
      tooltip: AppLocale.of(context).languageLabel,
      onPressed: () => showLanguagePicker(context),
      icon: const Icon(Icons.language),
    );
  }
}

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  String setting(SettingsText key, {String? name}) {
    final value = settingsCatalog[language.name]![key.index];
    return name == null ? value : value.replaceAll('{name}', name);
  }

  String drawer(String key, {int? count}) {
    final index = drawerKeys.indexOf(key);
    assert(index >= 0, 'Unknown drawer key: $key');
    final value = drawerCatalog[language.name]![index];
    return count == null ? value : value.replaceAll('{count}', '$count');
  }

  String approval(String key, {String? name, String? scope}) {
    final index = approvalKeys.indexOf(key);
    assert(index >= 0, 'Unknown approval key: $key');
    var value = approvalCatalog[language.name]![index];
    if (name != null) value = value.replaceAll('{name}', name);
    if (scope != null) value = value.replaceAll('{scope}', scope);
    return value;
  }

  String conversation(String key) {
    final index = conversationKeys.indexOf(key);
    assert(index >= 0, 'Unknown conversation key: $key');
    return conversationCatalog[language.name]![index];
  }

  String sessionStatus(dynamic value) => conversation(
    {
          'busy': 'busy',
          'retry': 'retrying',
          'idle': 'completed',
          'success': 'completed',
          'thinking': 'thinking',
          'alarm': 'approval',
          'error': 'error',
        }[value] ??
        'unknown',
  );

  // Translate only built-in demo fixtures. Real messages and user input stay intact.
  String demoValue(dynamic value, {required bool demo}) {
    final text = '${value ?? ''}';
    if (!demo) return text;
    for (final key in [
      'homeDevice',
      'refactor',
      'deadlock',
      'prices',
      'training',
      'cleanup',
      'shell',
    ]) {
      if (text == conversationCatalog['zh']![conversationKeys.indexOf(key)]) {
        return conversation(key);
      }
    }
    return text;
  }

  String get projectLinkUnavailable => mobile('projectLinkUnavailable');

  String workspace(String key) => mobile(key);

  String mobile(String key, {List<Object?> values = const []}) {
    final index = mobileKeys.indexOf(key);
    assert(index >= 0, 'Unknown mobile translation key: $key');
    final template = mobileCatalog[language.name]![index];
    // A single pass keeps user content containing placeholders intact.
    return template.replaceAllMapped(RegExp(r'\{v(\d+)\}'), (match) {
      final position = int.parse(match[1]!);
      assert(position < values.length, 'Missing value for $key');
      return '${values[position] ?? ''}';
    });
  }

  String errorText(Object? error) {
    final raw = '${error ?? ''}';
    if (raw.isEmpty) return raw;
    if (raw.startsWith('AgentTowerError:')) {
      final key = raw.substring('AgentTowerError:'.length);
      return mobile(mobileKeys.contains(key) ? key : 'requestFailed');
    }
    if (raw.contains('PlatformException(secure_storage,')) {
      return mobile('secureStorageFailed');
    }
    final key = serverErrorKeys[raw];
    if (key != null) {
      if (key == 'offline') return setting(SettingsText.offline);
      if (key == 'agentsUnavailable') return helpText('agentsLoadError');
      if (key == 'announcementsUnavailable') return announcementsUnavailable;
      return mobile(key);
    }
    final http = RegExp(r'^HTTP (\d{3})$').firstMatch(raw);
    if (http != null) return mobile('httpError', values: [http[1]]);
    // Unknown server diagnostics remain available in the API response; avoid
    // leaking untranslated server prose into the product's selected language.
    if (RegExp(r'[\u3400-\u9fff]').hasMatch(raw)) {
      return mobile('requestFailed');
    }
    return raw;
  }

  String text(String key) {
    final index = languageKeys.indexOf(key);
    assert(index >= 0, 'Unknown translation key: $key');
    return languageCatalog[language.name]![index];
  }

  String helpText(String key) {
    final index = helpKeys.indexOf(key);
    assert(index >= 0, 'Unknown help key: $key');
    return helpCatalog[language.name]![index];
  }

  String get appName => text('appName');

  // Select a complete content variant so titles and paragraphs stay together.
  Map localizedContent(Map item) {
    final variants = item['translations'];
    if (variants is! Map) return item;
    final keys = [
      language.name,
      if (language == AppLanguage.zhHant) ...['zh-Hant', 'zh-TW'],
      if (language == AppLanguage.zh) 'zh-CN',
      if (language != AppLanguage.zhHant) language.code,
      if (language != AppLanguage.zh) 'en',
    ];
    for (final key in keys) {
      final variant = variants[key];
      if (variant is Map) return {...item, ...variant};
    }
    return item;
  }

  String get retry => newsText[language.name]![0];
  String get noAnnouncements => newsText[language.name]![1];
  String get announcementsUnavailable => newsText[language.name]![2];
  String get connected => text('connected');
  String get menu => text('menu');
  String get announcement => text('announcement');
  String get announcementText => text('announcementText');
  String get viewAll => text('viewAll');
  String get connectComputer => text('connectComputer');
  String get heroTitle => text('heroTitle');
  String get heroCopy => text('heroCopy');
  String get windows => 'Windows';
  String get linux => 'Linux';
  String get macos => 'macOS';
  String get chooseTool => text('chooseTool');
  String get copyCommand => text('copyCommand');
  String get copyInstallCommand => text('copyInstallCommand');
  String get copyHint => text('copyHint');
  String get alreadyConnected => text('alreadyConnected');
  String get demo => text('demo');
  String get home => text('home');
  String get projects => text('projects');
  String get settings => text('settings');
  String get help => text('help');
  String get noProjects => text('noProjects');
  String get searchHint => text('searchHint');
  String get node => text('node');
  String get all => text('all');
  String get developerNews => text('developerNews');
  String get connectionSettings => text('connectionSettings');
  String get languageLabel => text('language');
  String get settingsCopy => text('settingsCopy');
  String get saveError => text('saveError');
}

const newsText = <String, List<String>>{
  'zh': ['重试', '暂无手机版公告', '公告加载失败'],
  'zhHant': ['重試', '暫無手機版公告', '公告載入失敗'],
  'en': [
    'Retry',
    'No mobile announcements yet',
    'Unable to load announcements',
  ],
  'ja': ['再試行', 'モバイル版のお知らせはありません', 'お知らせを読み込めません'],
  'ko': ['다시 시도', '모바일 공지가 없습니다', '공지를 불러올 수 없습니다'],
  'es': [
    'Reintentar',
    'Aún no hay anuncios para móviles',
    'No se pudieron cargar los anuncios',
  ],
  'fr': [
    'Réessayer',
    'Aucune annonce mobile pour le moment',
    'Impossible de charger les annonces',
  ],
  'de': [
    'Erneut versuchen',
    'Noch keine mobilen Ankündigungen',
    'Ankündigungen konnten nicht geladen werden',
  ],
  'pt': [
    'Tentar novamente',
    'Ainda não há anúncios para dispositivos móveis',
    'Não foi possível carregar os anúncios',
  ],
  'ru': [
    'Повторить',
    'Пока нет объявлений для мобильной версии',
    'Не удалось загрузить объявления',
  ],
  'ar': [
    'إعادة المحاولة',
    'لا توجد إعلانات للنسخة المحمولة بعد',
    'تعذّر تحميل الإعلانات',
  ],
  'hi': [
    'फिर कोशिश करें',
    'अभी मोबाइल संस्करण की कोई घोषणा नहीं है',
    'घोषणाएँ लोड नहीं हो सकीं',
  ],
  'id': [
    'Coba lagi',
    'Belum ada pengumuman versi seluler',
    'Gagal memuat pengumuman',
  ],
  'vi': [
    'Thử lại',
    'Chưa có thông báo cho phiên bản di động',
    'Không thể tải thông báo',
  ],
};

class AppLocale extends InheritedWidget {
  const AppLocale({
    super.key,
    required this.language,
    this.onChanged,
    required super.child,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage>? onChanged;
  static AppLocale? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocale>();

  static AppStrings of(BuildContext context) {
    final inherited = maybeOf(context);
    return AppStrings(inherited?.language ?? AppLanguage.zh);
  }

  @override
  bool updateShouldNotify(AppLocale oldWidget) =>
      language != oldWidget.language;
}
