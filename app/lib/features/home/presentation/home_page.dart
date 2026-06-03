import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/core/section_theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/responsive_grid.dart';
import 'package:app/shared/widgets/dashboard_tile.dart';
import 'package:app/shared/widgets/pf_button.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_typography.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? _user;
  bool _isLoading = true;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // ─── Section colors for dashboard tiles ───────────────────────────
  static const _tileColors = {
    'admin': Color(0xFF5E6AD2),
    'deepseek': Color(0xFF4FC3F7),
    'brain': Color(0xFFD2A8FF),
    'trading': Color(0xFFFCD535),
  };

  @override
  void initState() {
    super.initState();
    // Set home section skin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().setSection(SectionTheme.home);
      }
    });
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final userRepository = UserRepository(dioClient.dio);
      final user = await userRepository.getMe();
      if (mounted) {
        setState(() => _user = user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить профиль: $e'),
            backgroundColor: PfColors.destructive,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    final storage = SecureStorage();
    await storage.clearTokens();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _user?.roles?.contains('admin') ?? false;

    return AdaptiveScaffold(
      key: _scaffoldKey,
      title: 'Super App',
      currentPath: '/',
      username: _user?.username ?? 'Пользователь',
      userInitials:
          _user?.username != null ? _user!.username[0].toUpperCase() : '?',
      navDestinations: _buildNavDestinations(isAdmin),
      onLogout: _logout,
      actions: _user == null && !_isLoading
          ? [_buildAuthActions(context)]
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? _buildGuestView(context)
              : RefreshIndicator(
                  onRefresh: _loadUser,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: ResponsiveLayout.horizontalPadding(context)
                        .copyWith(top: 20, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Сервисы'),
                        const SizedBox(height: 20),
                        _buildDashboardGrid(isAdmin),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: PfTypography.displayMd.copyWith(color: PfColors.foreground),
        ),
        const SizedBox(height: 6),
        Container(
          width: 36,
          height: 3.5,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  // ─── Guest View ────────────────────────────────────────────────────
  Widget _buildGuestView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIconsFill.lockKey,
              size: 56,
              color: PfColors.mutedForeground.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Для того чтобы открыть контент\nавторизируйтесь или зарегистрируйтесь',
              textAlign: TextAlign.center,
              style: PfTypography.bodyLg.copyWith(
                color: PfColors.mutedForeground,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PfButton(
                  variant: 'primary',
                  size: 'pill',
                  label: 'Войти',
                  onPressed: () => context.go('/login'),
                ),
                const SizedBox(width: 16),
                PfButton(
                  variant: 'outline',
                  size: 'pill',
                  label: 'Регистрация',
                  onPressed: () => context.go('/register'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Auth actions (unauthenticated header) ─────────────────────────
  Widget _buildAuthActions(BuildContext context) {
    return PopupMenuButton<String>(
      icon: PhosphorIcon(
        PhosphorIconsFill.userCircle,
        color: PfColors.foreground,
        size: 22,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'login') context.go('/login');
        if (value == 'register') context.go('/register');
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'login',
          child: ListTile(
            leading: Icon(PhosphorIconsFill.signIn),
            title: Text('Войти'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const PopupMenuItem(
          value: 'register',
          child: ListTile(
            leading: Icon(PhosphorIconsFill.userPlus),
            title: Text('Регистрация'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  // ─── Nav Destinations ──────────────────────────────────────────────
  List<NavDestination> _buildNavDestinations(bool isAdmin) {
    // For unauthenticated users, only show Главная
    if (_user == null) {
      return [
        NavDestination(
          icon: PhosphorIconsFill.house,
          label: 'Главная',
          path: '/',
          isActive: true,
          section: SectionTheme.home,
        ),
      ];
    }

    final destinations = <NavDestination>[
      NavDestination(
        icon: PhosphorIconsFill.house,
        label: 'Главная',
        path: '/',
        isActive: true,
        section: SectionTheme.home,
      ),
      NavDestination(
        icon: PhosphorIconsFill.chartBar,
        label: 'Трейдинг',
        path: '/trading',
        section: SectionTheme.trading,
      ),
      NavDestination(
        icon: PhosphorIconsFill.musicNotes,
        label: 'Музыка',
        path: '/music',
        section: SectionTheme.music,
      ),
      NavDestination(
        icon: PhosphorIconsFill.videoCamera,
        label: 'Видео',
        path: '/video',
        section: SectionTheme.video,
      ),
    ];

    if (isAdmin) {
      destinations.insert(
        1,
        NavDestination(
          icon: PhosphorIconsFill.robot,
          label: 'Агенты',
          path: '/admin/agents',
          section: SectionTheme.admin,
        ),
      );
      destinations.insert(
        2,
        NavDestination(
          icon: PhosphorIconsFill.coin,
          label: 'DeepSeek',
          path: '/admin/deepseek-balance',
          section: SectionTheme.admin,
        ),
      );
      destinations.insert(
        3,
        NavDestination(
          icon: PhosphorIconsFill.brain,
          label: 'Мозг',
          path: '/admin/brain',
          section: SectionTheme.admin,
        ),
      );
    }

    return destinations;
  }

  // ─── Dashboard Grid ────────────────────────────────────────────────
  Widget _buildDashboardGrid(bool isAdmin) {
    final cards = <DashboardTileData>[];

    if (isAdmin) {
      cards.add(DashboardTileData(
        icon: PhosphorIconsFill.robot,
        title: 'Агенты',
        subtitle: 'Мониторинг системы',
        color: _tileColors['admin']!,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.admin);
          context.go('/admin/agents');
        },
        isHighlighted: true,
      ));
      cards.add(DashboardTileData(
        icon: PhosphorIconsFill.coin,
        title: 'DeepSeek',
        subtitle: 'Баланс API',
        color: _tileColors['deepseek']!,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.admin);
          context.go('/admin/deepseek-balance');
        },
      ));
      cards.add(DashboardTileData(
        icon: PhosphorIconsFill.brain,
        title: 'Мозг',
        subtitle: 'Второй мозг · граф знаний',
        color: _tileColors['brain']!,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.admin);
          context.go('/admin/brain');
        },
      ));
    }

    cards.addAll([
      DashboardTileData(
        icon: PhosphorIconsFill.chartBar,
        title: 'Трейдинг',
        subtitle: 'Стратегии · сделки · анализ',
        color: _tileColors['trading']!,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.trading);
          context.go('/trading');
        },
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.musicNotes,
        title: 'Музыка',
        subtitle: 'Медиатека',
        color: PfColors.accentMusic,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.music);
          context.go('/music');
        },
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.videoCamera,
        title: 'Видео',
        subtitle: 'Видеотека',
        color: PfColors.accentVideo,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.video);
          context.go('/video');
        },
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.fileText,
        title: 'Посты',
        subtitle: 'Заметки и статьи',
        color: PfColors.accentPosts,
        onTap: () {
          context.read<ThemeProvider>().setSection(SectionTheme.posts);
          context.go('/posts');
        },
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.mapPin,
        title: 'Карты',
        subtitle: 'Геолокация',
        color: PfColors.accentSettings,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Карты — скоро'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    ]);

    return ResponsiveGrid(
      spacing: 16,
      runSpacing: 16,
      mobileColumns: 2,
      desktopColumns: 4,
      itemCount: cards.length,
      itemBuilder: (context, index) => DashboardTile(
        data: cards[index],
        index: index,
      ),
    );
  }
}
