import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String kFavoritesBoxName = 'favorites';
const String kHistoryBoxName = 'history';

/// Hive boxes — opened in [main] before [runApp].
late Box<dynamic> favoritesBox;
late Box<dynamic> historyBox;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  favoritesBox = await Hive.openBox<dynamic>('favorites');
  historyBox = await Hive.openBox<dynamic>('history');
  runApp(const UApp());
}

// ——— Design tokens ———

abstract final class UAppColors {
  static const background = Color(0xFF07080D);
  static const surface = Color(0xFF12141C);
  static const accent = Color(0xFF818CF8);
  static const accentSecondary = Color(0xFFA78BFA);

  static const gradientStops = [
    Color(0xFF07080D),
    Color(0xFF0E1020),
    Color(0xFF141028),
    Color(0xFF0A0C14),
  ];
}

/// One tappable service that opens in [BrowserScreen].
class ServiceItem {
  final String name;
  final String url;
  final IconData icon;
  final Color accent;

  const ServiceItem({
    required this.name,
    required this.url,
    required this.icon,
    required this.accent,
  });
}

/// Favorites backed by Hive (persists across app restarts).
class FavoritesStore extends ChangeNotifier {
  FavoritesStore(this._box) {
    _loadFromHive();
  }

  final Box<dynamic> _box;
  final List<ServiceItem> _items = [];

  List<ServiceItem> get items => List.unmodifiable(_items);

  bool isFavorite(ServiceItem service) => _box.containsKey(service.url);

  void toggle(ServiceItem service) {
    if (isFavorite(service)) {
      _box.delete(service.url);
      _items.removeWhere((s) => s.url == service.url);
    } else {
      _box.put(service.url, {
        'name': service.name,
        'url': service.url,
      });
      _items.add(service);
    }
    notifyListeners();
  }

  void _loadFromHive() {
    _items.clear();
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is! Map) continue;
      final name = raw['name']?.toString();
      final url = raw['url']?.toString() ?? key.toString();
      if (name == null || name.isEmpty) continue;
      _items.add(serviceItemFromFavorite(name, url));
    }
  }
}

class FavoritesScope extends InheritedNotifier<FavoritesStore> {
  const FavoritesScope({
    super.key,
    required FavoritesStore store,
    required super.child,
  }) : super(notifier: store);

  static FavoritesStore of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<FavoritesScope>();
    assert(scope != null, 'FavoritesScope not found in widget tree');
    return scope!.notifier!;
  }
}

/// A single browsing history record.
class HistoryEntry {
  final String id;
  final String name;
  final String url;
  final DateTime visitedAt;

  const HistoryEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.visitedAt,
  });
}

/// Browsing history backed by Hive.
class HistoryStore extends ChangeNotifier {
  HistoryStore(this._box) {
    _loadFromHive();
  }

  final Box<dynamic> _box;
  final List<HistoryEntry> _items = [];

  List<HistoryEntry> get items => List.unmodifiable(_items);

  void recordVisit(String name, String url) {
    final visitedAt = DateTime.now();
    final id = visitedAt.millisecondsSinceEpoch.toString();
    _box.put(id, {
      'name': name,
      'url': url,
      'visitedAt': visitedAt.toIso8601String(),
    });
    _items.insert(
      0,
      HistoryEntry(id: id, name: name, url: url, visitedAt: visitedAt),
    );
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _box.clear();
    _items.clear();
    notifyListeners();
  }

  void _loadFromHive() {
    _items.clear();
    final entries = <HistoryEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is! Map) continue;
      final name = raw['name']?.toString();
      final url = raw['url']?.toString();
      final visitedRaw = raw['visitedAt']?.toString();
      if (name == null || url == null || visitedRaw == null) continue;
      entries.add(
        HistoryEntry(
          id: key.toString(),
          name: name,
          url: url,
          visitedAt: DateTime.tryParse(visitedRaw) ?? DateTime.now(),
        ),
      );
    }
    entries.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    _items.addAll(entries);
  }
}

class HistoryScope extends InheritedNotifier<HistoryStore> {
  const HistoryScope({
    super.key,
    required HistoryStore store,
    required super.child,
  }) : super(notifier: store);

  static HistoryStore of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<HistoryScope>();
    assert(scope != null, 'HistoryScope not found in widget tree');
    return scope!.notifier!;
  }
}

String formatVisitedAt(DateTime visitedAt) {
  final diff = DateTime.now().difference(visitedAt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  final local = visitedAt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} · $h:$m';
}

/// A labeled group of [ServiceItem]s shown on the home screen.
class AppCategory {
  final String title;
  final IconData icon;
  final Color accent;
  final List<ServiceItem> services;

  const AppCategory({
    required this.title,
    required this.icon,
    required this.accent,
    required this.services,
  });
}

const List<AppCategory> kHomeCategories = [
  AppCategory(
    title: 'Shopping',
    icon: Icons.shopping_bag_rounded,
    accent: Color(0xFFF59E0B),
    services: [
      ServiceItem(
        name: 'Amazon',
        url: 'https://www.amazon.in',
        icon: Icons.shopping_bag_outlined,
        accent: Color(0xFFFF9900),
      ),
      ServiceItem(
        name: 'Flipkart',
        url: 'https://www.flipkart.com',
        icon: Icons.storefront_outlined,
        accent: Color(0xFF2874F0),
      ),
    ],
  ),
  AppCategory(
    title: 'Fashion',
    icon: Icons.checkroom_rounded,
    accent: Color(0xFFEC4899),
    services: [
      ServiceItem(
        name: 'Myntra',
        url: 'https://www.myntra.com',
        icon: Icons.checkroom_outlined,
        accent: Color(0xFFFF3F6C),
      ),
      ServiceItem(
        name: 'AJIO',
        url: 'https://www.ajio.com',
        icon: Icons.style_outlined,
        accent: Color(0xFF2C4152),
      ),
    ],
  ),
  AppCategory(
    title: 'Food',
    icon: Icons.restaurant_rounded,
    accent: Color(0xFFF97316),
    services: [
      ServiceItem(
        name: 'Swiggy',
        url: 'https://www.swiggy.com',
        icon: Icons.delivery_dining_outlined,
        accent: Color(0xFFFC8019),
      ),
      ServiceItem(
        name: 'Zomato',
        url: 'https://www.zomato.com',
        icon: Icons.restaurant_outlined,
        accent: Color(0xFFE23744),
      ),
    ],
  ),
  AppCategory(
    title: 'Grocery',
    icon: Icons.local_grocery_store_rounded,
    accent: Color(0xFF22C55E),
    services: [
      ServiceItem(
        name: 'Blinkit',
        url: 'https://blinkit.com',
        icon: Icons.flash_on_rounded,
        accent: Color(0xFFF8CB46),
      ),
      ServiceItem(
        name: 'BigBasket',
        url: 'https://www.bigbasket.com',
        icon: Icons.shopping_cart_outlined,
        accent: Color(0xFF84C225),
      ),
    ],
  ),
  AppCategory(
    title: 'Ride',
    icon: Icons.directions_car_rounded,
    accent: Color(0xFF38BDF8),
    services: [
      ServiceItem(
        name: 'Rapido',
        url: 'https://www.rapido.bike',
        icon: Icons.two_wheeler_outlined,
        accent: Color(0xFFFFD700),
      ),
      ServiceItem(
        name: 'Uber',
        url: 'https://www.uber.com/in/en/',
        icon: Icons.local_taxi_outlined,
        accent: Color(0xFFE5E5E5),
      ),
    ],
  ),
];

/// Restores full [ServiceItem] UI fields from Hive name/url.
ServiceItem serviceItemFromFavorite(String name, String url) {
  for (final category in kHomeCategories) {
    for (final service in category.services) {
      if (service.url == url) return service;
    }
  }
  return ServiceItem(
    name: name,
    url: url,
    icon: Icons.language_rounded,
    accent: UAppColors.accent,
  );
}

class UApp extends StatelessWidget {
  const UApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: UAppColors.accent,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'U-APP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: UAppColors.background,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ——— Splash ———

const String kUAppLogoAsset = 'assets/images/uapp_logo.png';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
    Future<void>.delayed(const Duration(seconds: 3), _navigateToHome);
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionDuration: const Duration(milliseconds: 650),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UAppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _GradientBackground(),
          FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: UAppColors.accent.withValues(alpha: 0.35),
                              blurRadius: 48,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: UAppColors.accentSecondary
                                  .withValues(alpha: 0.2),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            kUAppLogoAsset,
                            width: 132,
                            height: 132,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Colors.white,
                            Color(0xFFE0E7FF),
                            UAppColors.accent,
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'U-APP',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Unified Application Platform',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                          letterSpacing: 0.4,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void openBrowser(BuildContext context, String title, String url) {
  HistoryScope.of(context).recordVisit(title, url);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BrowserScreen(title: title, url: url),
    ),
  );
}

// ——— Main shell & bottom navigation ———

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final FavoritesStore _favoritesStore = FavoritesStore(favoritesBox);
  late final HistoryStore _historyStore = HistoryStore(historyBox);
  int _currentIndex = 0;

  @override
  void dispose() {
    _favoritesStore.dispose();
    _historyStore.dispose();
    super.dispose();
  }

  static const _tabs = [
    _NavTab(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    _NavTab(
      label: 'Search',
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
    ),
    _NavTab(
      label: 'Favorites',
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
    ),
    _NavTab(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FavoritesScope(
      store: _favoritesStore,
      child: HistoryScope(
        store: _historyStore,
        child: Scaffold(
        extendBody: true,
        backgroundColor: UAppColors.background,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: switch (_currentIndex) {
            0 => const HomeScreen(key: ValueKey('home')),
            1 => const SearchScreen(key: ValueKey('search')),
            2 => const FavoritesScreen(key: ValueKey('favorites')),
            3 => const ProfileScreen(key: ValueKey('profile')),
            _ => const HomeScreen(key: ValueKey('home')),
          },
        ),
        bottomNavigationBar: _ModernBottomNavBar(
          tabs: _tabs,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
        ),
      ),
      ),
    );
  }
}

class _NavTab {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class _ModernBottomNavBar extends StatelessWidget {
  final List<_NavTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _ModernBottomNavBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            UAppColors.surface.withValues(alpha: 0.98),
            UAppColors.surface.withValues(alpha: 0.88),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: UAppColors.accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final tab = tabs[index];
          final selected = index == currentIndex;
          return Expanded(
            child: _BottomNavItem(
              label: tab.label,
              icon: selected ? tab.activeIcon : tab.icon,
              selected: selected,
              onTap: () => onTap(index),
            ),
          );
        }),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? UAppColors.accent.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                child: Icon(
                  icon,
                  size: 24,
                  color: selected
                      ? UAppColors.accent
                      : Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 280),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? UAppColors.accent
                      : Colors.white.withValues(alpha: 0.45),
                  letterSpacing: 0.2,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ——— Tab screens ———

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const _GradientBackground(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              const _StylishAppBar(),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const _WelcomeHeader(),
                    const SizedBox(height: 32),
                    ...List.generate(kHomeCategories.length, (index) {
                      final category = kHomeCategories[index];
                      return _AnimatedSection(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PremiumCategoryHeader(category: category),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  for (var i = 0;
                                      i < category.services.length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(width: 16),
                                    Expanded(
                                      child: _AnimatedServiceCard(
                                        animationIndex: index * 2 + i,
                                        service: category.services[i],
                                        onTap: () => openBrowser(
                                          context,
                                          category.services[i].name,
                                          category.services[i].url,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Encodes a search query for URL use (spaces → `+`).
String encodeSearchQuery(String query) {
  return query.trim().replaceAll(' ', '+');
}

class _SearchPlatform {
  final String name;
  final IconData icon;
  final Color accent;
  final String Function(String encodedQuery) buildUrl;

  const _SearchPlatform({
    required this.name,
    required this.icon,
    required this.accent,
    required this.buildUrl,
  });

  String optionLabel(String rawQuery) => 'Search on $name';

  String searchUrl(String rawQuery) => buildUrl(encodeSearchQuery(rawQuery));
}

final List<_SearchPlatform> _searchPlatforms = [
  _SearchPlatform(
    name: 'Amazon',
    icon: Icons.shopping_bag_outlined,
    accent: const Color(0xFFFF9900),
    buildUrl: (q) => 'https://www.amazon.in/s?k=$q',
  ),
  _SearchPlatform(
    name: 'Flipkart',
    icon: Icons.storefront_outlined,
    accent: const Color(0xFF2874F0),
    buildUrl: (q) => 'https://www.flipkart.com/search?q=$q',
  ),
  _SearchPlatform(
    name: 'Myntra',
    icon: Icons.checkroom_outlined,
    accent: const Color(0xFFFF3F6C),
    buildUrl: (q) => 'https://www.myntra.com/$q',
  ),
  _SearchPlatform(
    name: 'AJIO',
    icon: Icons.style_outlined,
    accent: const Color(0xFF2C4152),
    buildUrl: (q) => 'https://www.ajio.com/search/?text=$q',
  ),
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  bool get _hasQuery => _query.trim().isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openPlatformSearch(_SearchPlatform platform) {
    final trimmed = _query.trim();
    if (trimmed.isEmpty) return;
    openBrowser(
      context,
      platform.optionLabel(trimmed),
      platform.searchUrl(trimmed),
    );
  }

  InputDecoration _searchFieldDecoration() {
    return InputDecoration(
      hintText: 'Search products or services...',
      hintStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
      ),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: UAppColors.accent.withValues(alpha: 0.9),
      ),
      suffixIcon: _hasQuery
          ? IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            )
          : null,
      filled: true,
      fillColor: UAppColors.surface.withValues(alpha: 0.85),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: UAppColors.accent.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const _GradientBackground(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        UAppColors.surface.withValues(alpha: 0.95),
                        UAppColors.surface.withValues(alpha: 0.72),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
                title: const Text(
                  'Search',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      'Search across top stores',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      decoration: _searchFieldDecoration(),
                    ),
                    if (_hasQuery) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Results for "${_query.trim()}"',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: UAppColors.accent.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._searchPlatforms.map(
                        (platform) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SearchPlatformOptionTile(
                            label: platform.optionLabel(_query),
                            icon: platform.icon,
                            accent: platform.accent,
                            onTap: () => _openPlatformSearch(platform),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 32),
                      Icon(
                        Icons.travel_explore_rounded,
                        size: 48,
                        color: UAppColors.accent.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Type to search on Amazon, Flipkart,\nMyntra, or AJIO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchPlatformOptionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _SearchPlatformOptionTile({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                UAppColors.surface.withValues(alpha: 0.92),
                UAppColors.surface.withValues(alpha: 0.75),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.3),
                        accent.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_browser_rounded,
                  size: 20,
                  color: UAppColors.accent.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FavoritesScope.of(context);
    final favorites = store.items;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const _GradientBackground(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        UAppColors.surface.withValues(alpha: 0.95),
                        UAppColors.surface.withValues(alpha: 0.72),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
                title: const Text(
                  'Favorites',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
                sliver: favorites.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.favorite_border_rounded,
                              size: 56,
                              color: UAppColors.accent.withValues(alpha: 0.35),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'No favorites yet',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tap the heart on any service\non Home to save it here',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildListDelegate([
                          Text(
                            '${favorites.length} saved service${favorites.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: UAppColors.accent.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...favorites.map(
                            (service) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _FavoriteServiceTile(
                                service: service,
                                onOpen: () => openBrowser(
                                  context,
                                  service.name,
                                  service.url,
                                ),
                                onRemove: () => store.toggle(service),
                              ),
                            ),
                          ),
                        ]),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteServiceTile extends StatelessWidget {
  final ServiceItem service;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _FavoriteServiceTile({
    required this.service,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                UAppColors.surface.withValues(alpha: 0.92),
                UAppColors.surface.withValues(alpha: 0.75),
              ],
            ),
            border: Border.all(
              color: service.accent.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: service.accent.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        service.accent.withValues(alpha: 0.3),
                        service.accent.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: service.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(service.icon, color: service.accent, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    service.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                _FavoriteHeartButton(
                  service: service,
                  isFavorite: true,
                  onToggle: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteHeartButton extends StatelessWidget {
  final ServiceItem service;
  final bool isFavorite;
  final VoidCallback? onToggle;

  const _FavoriteHeartButton({
    required this.service,
    this.isFavorite = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final store = FavoritesScope.of(context);
    final favorited = onToggle != null ? isFavorite : store.isFavorite(service);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle ?? () => store.toggle(service),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Icon(
              favorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              key: ValueKey(favorited),
              size: 20,
              color: favorited
                  ? const Color(0xFFEC4899)
                  : Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final historyCount = HistoryScope.of(context).items.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const _GradientBackground(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        UAppColors.surface.withValues(alpha: 0.95),
                        UAppColors.surface.withValues(alpha: 0.72),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
                title: const Text(
                  'Profile',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              UAppColors.accent,
                              UAppColors.accentSecondary,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: UAppColors.accent.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Your profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unified Application Platform',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Activity',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: UAppColors.accent.withValues(alpha: 0.95),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ProfileMenuTile(
                      icon: Icons.history_rounded,
                      title: 'Browsing History',
                      subtitle: historyCount == 0
                          ? 'No visits yet'
                          : '$historyCount visit${historyCount == 1 ? '' : 's'} saved',
                      onTap: () {
                        final historyStore = HistoryScope.of(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => HistoryScope(
                              store: historyStore,
                              child: const HistoryScreen(),
                            ),
                          ),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                UAppColors.surface.withValues(alpha: 0.92),
                UAppColors.surface.withValues(alpha: 0.75),
              ],
            ),
            border: Border.all(
              color: UAppColors.accent.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: UAppColors.accent.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        UAppColors.accent.withValues(alpha: 0.35),
                        UAppColors.accent.withValues(alpha: 0.12),
                      ],
                    ),
                    border: Border.all(
                      color: UAppColors.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(icon, color: UAppColors.accent, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _confirmClearAll(BuildContext context) async {
    final store = HistoryScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UAppColors.surface,
        title: const Text('Clear history?'),
        content: Text(
          'Remove all ${store.items.length} browsing records. This cannot be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Clear all',
              style: TextStyle(color: Color(0xFFEC4899)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await store.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = HistoryScope.of(context);
    final history = store.items;

    return Scaffold(
      backgroundColor: UAppColors.background,
      appBar: AppBar(
        title: const Text(
          'Browsing History',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: UAppColors.surface,
        foregroundColor: Colors.white,
        actions: [
          if (history.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context),
              child: const Text(
                'Clear all',
                style: TextStyle(color: Color(0xFFEC4899)),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          const _GradientBackground(),
          history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 56,
                          color: UAppColors.accent.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No history yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Open a service from Home, Search,\nor Favorites to see it here',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    final service = serviceItemFromFavorite(entry.name, entry.url);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryTile(
                        entry: entry,
                        accent: service.accent,
                        icon: service.icon,
                        onTap: () => openBrowser(
                          context,
                          entry.name,
                          entry.url,
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.entry,
    required this.accent,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                UAppColors.surface.withValues(alpha: 0.92),
                UAppColors.surface.withValues(alpha: 0.75),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: accent.withValues(alpha: 0.15),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: UAppColors.accent.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatVisitedAt(entry.visitedAt),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: UAppColors.accent.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_browser_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: UAppColors.gradientStops,
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _GlowOrb(
              color: UAppColors.accent.withValues(alpha: 0.22),
              size: 280,
            ),
          ),
          Positioned(
            bottom: 80,
            left: -100,
            child: _GlowOrb(
              color: UAppColors.accentSecondary.withValues(alpha: 0.14),
              size: 240,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _StylishAppBar extends StatelessWidget {
  const _StylishAppBar();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: true,
      expandedHeight: 72,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              UAppColors.surface.withValues(alpha: 0.95),
              UAppColors.surface.withValues(alpha: 0.72),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [UAppColors.accent, UAppColors.accentSecondary],
              ),
              boxShadow: [
                BoxShadow(
                  color: UAppColors.accent.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.apps_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Color(0xFFC7D2FE)],
            ).createShader(bounds),
            child: const Text(
              'U-APP',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      centerTitle: false,
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFE0E7FF), Color(0xFFA5B4FC)],
          ).createShader(bounds),
          child: const Text(
            'Welcome to U-APP',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'One app for all services',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: Colors.white.withValues(alpha: 0.55),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: UAppColors.accent.withValues(alpha: 0.12),
            border: Border.all(
              color: UAppColors.accent.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 16,
                color: UAppColors.accent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                '10 services · 5 categories',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: UAppColors.accent.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiumCategoryHeader extends StatelessWidget {
  final AppCategory category;

  const _PremiumCategoryHeader({required this.category});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                category.accent.withValues(alpha: 0.25),
                category.accent.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color: category.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Icon(category.icon, color: category.accent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 3,
                width: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      category.accent,
                      category.accent.withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedSection extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedSection({required this.index, required this.child});

  @override
  State<_AnimatedSection> createState() => _AnimatedSectionState();
}

class _AnimatedSectionState extends State<_AnimatedSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future<void>.delayed(Duration(milliseconds: 80 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _AnimatedServiceCard extends StatefulWidget {
  final int animationIndex;
  final ServiceItem service;
  final VoidCallback onTap;

  const _AnimatedServiceCard({
    required this.animationIndex,
    required this.service,
    required this.onTap,
  });

  @override
  State<_AnimatedServiceCard> createState() => _AnimatedServiceCardState();
}

class _AnimatedServiceCardState extends State<_AnimatedServiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceScale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _entranceScale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    Future<void>.delayed(
      Duration(milliseconds: 60 * widget.animationIndex + 120),
      () {
        if (mounted) _entranceController.forward();
      },
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    final accent = widget.service.accent;

    return ScaleTransition(
      scale: _entranceScale,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  UAppColors.surface.withValues(alpha: 0.95),
                  UAppColors.surface.withValues(alpha: 0.7),
                ],
              ),
              border: Border.all(
                color: _pressed
                    ? accent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: _pressed ? 0.2 : 0.1),
                  blurRadius: _pressed ? 24 : 16,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: 0.92,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: 0.35),
                                accent.withValues(alpha: 0.12),
                              ],
                            ),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            widget.service.icon,
                            color: accent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.service.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: _FavoriteHeartButton(service: widget.service),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrowserScreen extends StatefulWidget {
  final String title;
  final String url;

  const BrowserScreen({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController controller;
  double progress = 0;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            setState(() {
              progress = value / 100;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UAppColors.background,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: UAppColors.surface,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: controller.reload,
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 1)
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              color: UAppColors.accent,
            ),
          Expanded(
            child: WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
