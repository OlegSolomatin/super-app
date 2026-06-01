import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = true;
  bool _isSaving = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final userRepository = UserRepository(dioClient.dio);
      final user = await userRepository.getMe();
      if (mounted) {
        setState(() {
          _user = user;
          _usernameController.text = user.username;
          _bioController.text = user.bio ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить профиль: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final userRepository = UserRepository(dioClient.dio);

      final updated = await userRepository.updateMe(
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _user = updated;
          _usernameController.text = updated.username;
          _bioController.text = updated.bio ?? '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Настройки сохранены'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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

  /// Navigation destinations for the desktop sidebar.
  List<NavDestination> _buildNavDestinations() {
    final isAdmin = _user?.roles?.contains('admin') ?? false;
    final destinations = <NavDestination>[
      NavDestination(
        icon: const Icon(PhosphorIconsFill.house, size: 20),
        label: 'Главная',
        path: '/',
        isActive: false,
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

  Widget _buildDrawer(BuildContext context, ThemeProvider themeProvider, bool isDark) {
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
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go('/settings');
                      },
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      key: _scaffoldKey,
      title: 'Настройки',
      currentPath: '/settings',
      navDestinations: _buildNavDestinations(),
      drawer: _buildDrawer(context, themeProvider, isDark),
      onLogout: _logout,
      actions: [
        IconButton(
          icon: const Icon(PhosphorIconsFill.house, size: 22),
          tooltip: 'На главную',
          onPressed: () => context.go('/'),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: ResponsiveLayout.horizontalPadding(context)
                  .copyWith(top: 32, bottom: 32),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Avatar
                        Center(
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.accentColor,
                                  Color(0xFF9B7CFF)
                                ],
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
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _user?.email ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.textSecondary
                                : AppTheme.lightTextSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Username
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Имя пользователя',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Введите имя пользователя';
                            }
                            if (value.trim().length < 2) {
                              return 'Минимум 2 символа';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Bio
                        TextFormField(
                          controller: _bioController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'О себе',
                            prefixIcon: Icon(Icons.info_outline),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Save button
                        ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Сохранить',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Menu item for the mobile drawer.
class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Theme mode segmented control for the drawer.
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
    return Row(
      children: [
        _ThemeToggleButton(
          icon: Icons.dark_mode,
          label: 'Тёмная',
          selected: current == ThemeModePreference.dark,
          isDark: isDark,
          onTap: () => onChanged(ThemeModePreference.dark),
        ),
        const SizedBox(width: 8),
        _ThemeToggleButton(
          icon: Icons.phone_android,
          label: 'Системная',
          selected: current == ThemeModePreference.system,
          isDark: isDark,
          onTap: () => onChanged(ThemeModePreference.system),
        ),
        const SizedBox(width: 8),
        _ThemeToggleButton(
          icon: Icons.light_mode,
          label: 'Светлая',
          selected: current == ThemeModePreference.light,
          isDark: isDark,
          onTap: () => onChanged(ThemeModePreference.light),
        ),
      ],
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? (selected ? AppTheme.accentColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06))
        : (selected ? AppTheme.accentColor.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05));

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: AppTheme.accentColor, width: 1)
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? AppTheme.accentColor
                    : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: selected
                      ? AppTheme.accentColor
                      : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
