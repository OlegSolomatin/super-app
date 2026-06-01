import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/responsive_grid.dart';
import 'package:app/shared/widgets/dashboard_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? _user;
  bool _isLoading = true;


  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();

    _loadUser();
  }


  @override
  void dispose() {

    super.dispose();
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
            backgroundColor: Colors.red.shade800,
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
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
        key: _scaffoldKey,
        title: 'Super App',
        currentPath: '/',
        navDestinations: _buildNavDestinations(),
        drawer: _buildDrawer(context, themeProvider, isDark),
        onLogout: _logout,
        actions: _user == null && !_isLoading
            ? [_buildAuthActions(context)]
            : null,
        body: Stack(
        children: [
          _buildBackgroundPattern(isDark),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _user == null
                  ? _buildGuestView(context, themeProvider, isDark)
                  : RefreshIndicator(
                      onRefresh: _loadUser,
                      child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: ResponsiveLayout.horizontalPadding(context).copyWith(top: 20, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Сервисы',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 36,
                              height: 3.5,
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildDashboardGrid(),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// Guest view — shown instead of dashboard tiles for unauthenticated users.
  Widget _buildGuestView(
      BuildContext context, ThemeProvider themeProvider, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsFill.lockKey,
              size: 56,
              color: isDark
                  ? AppTheme.textSecondary.withValues(alpha: 0.5)
                  : AppTheme.lightTextSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Для того чтобы открыть контент\nавторизируйтесь или зарегистрируйтесь',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.lightTextSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildGuestButton(
                  context,
                  label: 'Войти',
                  isPrimary: true,
                  onTap: () => context.go('/login'),
                ),
                const SizedBox(width: 16),
                _buildGuestButton(
                  context,
                  label: 'Регистрация',
                  isPrimary: false,
                  onTap: () => context.go('/register'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestButton(
    BuildContext context, {
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isPrimary) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15)),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark
            ? AppTheme.textPrimary
            : AppTheme.lightTextPrimary,
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.15),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15)),
    );
  }

  /// PopupMenuButton for unauthenticated users — shown in header/appbar.
  Widget _buildAuthActions(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        PhosphorIconsFill.userCircle,
        color: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.textPrimary
            : AppTheme.lightTextPrimary,
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

  /// Navigation destinations for the desktop sidebar.
  List<NavDestination> _buildNavDestinations() {
    final isAdmin = _user?.roles?.contains('admin') ?? false;
    final destinations = <NavDestination>[
      NavDestination(
        icon: const Icon(PhosphorIconsFill.house, size: 20),
        label: 'Главная',
        path: '/',
        isActive: true,
      ),
      NavDestination(
        icon: const Icon(PhosphorIconsFill.chartLine, size: 20),
        label: 'Трейдинг',
        path: '/trading',
      ),
      NavDestination(
        icon: const Icon(PhosphorIconsFill.musicNotes, size: 20),
        label: 'Музыка',
        path: '/music',
      ),
      NavDestination(
        icon: const Icon(PhosphorIconsFill.videoCamera, size: 20),
        label: 'Видео',
        path: '/video',
      ),
    ];

    if (isAdmin) {
      destinations.insert(
        1,
        NavDestination(
          icon: const Icon(PhosphorIconsFill.robot, size: 20),
          label: 'Агенты',
          path: '/admin/agents',
        ),
      );
      destinations.insert(
        2,
        NavDestination(
          icon: const Icon(PhosphorIconsFill.coin, size: 20),
          label: 'DeepSeek',
          path: '/admin/deepseek-balance',
        ),
      );
      destinations.insert(
        3,
        NavDestination(
          icon: const Icon(PhosphorIconsFill.brain, size: 20),
          label: 'Мозг',
          path: '/admin/brain',
        ),
      );
    }

    return destinations;
  }

  Widget _buildDrawer(
      BuildContext context, ThemeProvider themeProvider, bool isDark) {
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final surface =
        isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;

    return Drawer(
      width: MediaQuery.of(context).size.width,
      child: Container(
        color: isDark
            ? AppTheme.bgColor.withValues(alpha: 0.98)
            : AppTheme.lightBgColor.withValues(alpha: 0.98),
        child: SafeArea(
          child: Column(
            children: [
              // Profile section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: 0.5),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Avatar placeholder
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.accentColor, Color(0xFF9B7CFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _user?.username != null
                              ? _user!.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _user?.username ?? 'Пользователь',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _user?.email ?? '',
                      style: TextStyle(
                        color: subColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Menu items
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(
                        height: 1,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    _DrawerMenuItem(
                      icon: Icons.person_outline,
                      title: 'Профиль',
                      isDark: isDark,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _DrawerMenuItem(
                      icon: Icons.settings_outlined,
                      title: 'Настройки',
                      isDark: isDark,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _DrawerMenuItem(
                      icon: Icons.info_outline,
                      title: 'О приложении',
                      isDark: isDark,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Bottom pinned: theme toggle
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: 0.5),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Logout button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _logout();
                        },
                        icon: const Icon(
                          Icons.logout,
                          color: Color(0xFFE53935),
                          size: 20,
                        ),
                        label: const Text(
                          'Выйти',
                          style: TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Тема',
                      style: TextStyle(
                        color: subColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ThemeSegmentedControl(
                      current: themeProvider.mode,
                      onChanged: (mode) {
                        themeProvider.setMode(mode);
                        Navigator.of(context).pop();
                      },
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundPattern(bool isDark) {
    if (!isDark) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                AppTheme.accentColor.withValues(alpha: 0.04),
                AppTheme.accentColor.withValues(alpha: 0.01),
                Colors.transparent,
              ],
              radius: 0.7,
              center: const Alignment(-0.3, -0.3),
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardGrid() {
    final cards = <DashboardTileData>[];

    // Admin card — first, only for admin users
    final isAdmin = _user?.roles?.contains('admin') ?? false;
    if (isAdmin) {
      cards.add(DashboardTileData(
        icon: PhosphorIconsFill.robot,
        title: 'Агенты',
        subtitle: 'Мониторинг системы',
        color: const Color(0xFF7C5CFC),
        onTap: () => context.go('/admin/agents'),
        isHighlighted: true,
      ));
      cards.add(DashboardTileData(
        icon: PhosphorIconsFill.coin,
        title: 'DeepSeek',
        subtitle: 'Баланс API',
        color: const Color(0xFF4FC3F7),
        onTap: () => context.go('/admin/deepseek-balance'),
      ));
      cards.add(DashboardTileData(
        icon: PhosphorIconsFill.brain,
        title: 'Мозг',
        subtitle: 'Второй мозг · граф знаний',
        color: const Color(0xFFD2A8FF),
        onTap: () => context.go('/admin/brain'),
      ));
    }

    cards.addAll([
      DashboardTileData(
        icon: PhosphorIconsFill.fileText,
        title: 'Посты',
        subtitle: 'Читайте и создавайте посты',
        color: const Color(0xFF4FC3F7),
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.barbell,
        title: 'Тренировки',
        subtitle: 'Планируйте тренировки',
        color: const Color(0xFF81C784),
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.musicNotes,
        title: 'Музыка',
        subtitle: 'Слушайте музыку',
        color: const Color(0xFFCE93D8),
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.videoCamera,
        title: 'Видео',
        subtitle: 'Смотрите видео',
        color: const Color(0xFFFF8A65),
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.mapPin,
        title: 'Карты',
        subtitle: 'Исследуйте карты',
        color: const Color(0xFF4DB6AC),
      ),
      DashboardTileData(
        icon: PhosphorIconsFill.chartLine,
        title: 'Трейдинг',
        subtitle: 'Зарабатывайте на трейдинге',
        color: const Color(0xFFFFD700),
        onTap: () => context.go('/trading'),
      ),
    ]);

    return ResponsiveGrid(
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return DashboardTile(
          data: card,
          index: index,
        );
      },
      mobileColumns: 2,
      tabletColumns: 3,
      desktopColumns: 4,
      childAspectRatio: 1.1,
    );
  }
}

// ─── Drawer Menu Item ────────────────────────────────────────────────────────

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final bool isDark;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor =
        isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final itemColor = color ?? defaultColor;

    return ListTile(
      leading: Icon(icon, color: itemColor),
      title: Text(
        title,
        style: TextStyle(
          color: itemColor,
          fontSize: 16,
          fontWeight: color != null ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      onTap: onTap,
    );
  }
}

// ─── Theme Segmented Control ─────────────────────────────────────────────────

class _ThemeSegmentedControl extends StatelessWidget {
  final ThemeModePreference current;
  final ValueChanged<ThemeModePreference> onChanged;
  final bool isDark;

  const _ThemeSegmentedControl({
    required this.current,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (icon: '🌙', label: 'Тёмная', value: ThemeModePreference.dark),
      (icon: '💻', label: 'Системная', value: ThemeModePreference.system),
      (icon: '☀️', label: 'Светлая', value: ThemeModePreference.light),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((opt) {
          final isActive = current == opt.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opt.icon,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      opt.label,
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.5)
                                : Colors.black.withValues(alpha: 0.5)),
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Drawer Menu Item ────────────────────────────────────────────────────────
