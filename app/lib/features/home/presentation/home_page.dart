import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  User? _user;
  bool _isLoading = true;
  bool _showBanner = true;

  late final AnimationController _bannerController;
  late final Animation<double> _bannerOpacity;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bannerOpacity = CurvedAnimation(
      parent: _bannerController,
      curve: Curves.easeOut,
    );
    _loadUser();
  }

  void _startBannerTimer() {
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        _bannerController.forward().then((_) {
          if (mounted) setState(() => _showBanner = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _bannerController.dispose();
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
        _startBannerTimer();
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

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Super App'),
        backgroundColor: isDark
            ? AppTheme.bgColor.withValues(alpha: 0.85)
            : AppTheme.lightSurfaceColor.withValues(alpha: 0.85),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Меню',
          ),
        ],
      ),
      endDrawer: _buildDrawer(context, themeProvider, isDark),
      body: Stack(
        children: [
          // Subtle background pattern — only on dark theme
          _buildBackgroundPattern(isDark),
          // Main content
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadUser,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome section — auto-hides after 15s
                        if (_showBanner) ...[
                          FadeTransition(
                            opacity: _bannerOpacity,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.accentColor,
                                    Color(0xFF9B7CFF)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Привет, ${_user?.username ?? 'Пользователь'}!',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _user?.email ?? '',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        // Elegant "Сервисы" header with accent underline
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
                    // Logout — first, red
                    _DrawerMenuItem(
                      icon: Icons.logout,
                      title: 'Выйти',
                      color: const Color(0xFFE53935),
                      isDark: isDark,
                      onTap: () {
                        Navigator.of(context).pop();
                        _logout();
                      },
                    ),
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
    final cards = <_DashboardCardData>[];

    // Admin card — first, only for admin users
    final isAdmin = _user?.roles?.contains('admin') ?? false;
    if (isAdmin) {
      cards.add(_DashboardCardData(
        icon: Icons.monitor_heart,
        title: 'Агенты',
        subtitle: 'Мониторинг системы',
        color: const Color(0xFF7C5CFC),
        onTap: () => context.go('/admin/agents'),
        isHighlighted: true,
      ));
    }

    cards.addAll([
      _DashboardCardData(
        icon: Icons.article_outlined,
        title: 'Посты',
        subtitle: 'Читайте и создавайте посты',
        color: const Color(0xFF4FC3F7),
      ),
      _DashboardCardData(
        icon: Icons.fitness_center,
        title: 'Тренировки',
        subtitle: 'Планируйте тренировки',
        color: const Color(0xFF81C784),
      ),
      _DashboardCardData(
        icon: Icons.music_note,
        title: 'Музыка',
        subtitle: 'Слушайте музыку',
        color: const Color(0xFFCE93D8),
      ),
      _DashboardCardData(
        icon: Icons.videocam,
        title: 'Видео',
        subtitle: 'Смотрите видео',
        color: const Color(0xFFFF8A65),
      ),
      _DashboardCardData(
        icon: Icons.map,
        title: 'Карты',
        subtitle: 'Исследуйте карты',
        color: const Color(0xFF4DB6AC),
      ),
    ]);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return _DashboardCard(
          data: card,
          index: index,
        );
      },
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

// ─── Dashboard Card Data ─────────────────────────────────────────────────────

class _DashboardCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const _DashboardCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.isHighlighted = false,
  });
}

// ─── Dashboard Card ──────────────────────────────────────────────────────────

class _DashboardCard extends StatefulWidget {
  final _DashboardCardData data;
  final int index;

  const _DashboardCard({required this.data, required this.index});

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );
    if (widget.data.isHighlighted) {
      _pulseCtrl.repeat(reverse: true);
    }

    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = widget.data.isHighlighted;
    final pulseVal = _pulseAnim.value;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            final tap = widget.data.onTap;
            if (tap != null) {
              tap();
            } else {
              _showComingSoon();
            }
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAdmin
                          ? AppTheme.accentColor
                              .withValues(alpha: 0.25 + 0.35 * pulseVal)
                          : isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.06),
                      width: isAdmin ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (isAdmin)
                        BoxShadow(
                          color: AppTheme.accentColor
                              .withValues(alpha: 0.12 + 0.18 * pulseVal),
                          blurRadius: 12 + 10 * pulseVal,
                          spreadRadius: 1 * pulseVal,
                        )
                      else
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      children: [
                        // Background layer: glassmorphism (dark) or white (light)
                        Positioned.fill(
                          child: isDark
                              ? _buildGlassBackground()
                              : _buildLightBackground(),
                        ),
                        // Decorative semi-transparent icon in background
                        if (isDark)
                          Positioned(
                            right: -8,
                            bottom: -8,
                            child: Opacity(
                              opacity: 0.05,
                              child: Icon(
                                widget.data.icon,
                                size: 80,
                                color: widget.data.color,
                              ),
                            ),
                          ),
                        // Content layer
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              final tap = widget.data.onTap;
                              if (tap != null) {
                                tap();
                              } else {
                                _showComingSoon();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  // Gradient icon with glow
                                  _buildIconWithGradient(isAdmin, isDark),
                                  const SizedBox(height: 14),
                                  Text(
                                    widget.data.title,
                                    style: TextStyle(
                                      color: isDark
                                          ? AppTheme.textPrimary
                                          : AppTheme.lightTextPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.data.subtitle,
                                    style: TextStyle(
                                      color: isDark
                                          ? AppTheme.textSecondary
                                          : AppTheme.lightTextSecondary,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.data.color.withValues(alpha: 0.12),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildLightBackground() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCardColor,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildIconWithGradient(bool isAdmin, bool isDark) {
    final iconSize = isAdmin ? 30.0 : 26.0;
    final containerSize = isAdmin ? 56.0 : 52.0;

    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            widget.data.color.withValues(alpha: 0.25),
            widget.data.color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: widget.data.color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              widget.data.color,
              widget.data.color.withValues(alpha: 0.6),
            ],
          ).createShader(bounds),
          child: Icon(
            widget.data.icon,
            size: iconSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.data.title} — скоро'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
