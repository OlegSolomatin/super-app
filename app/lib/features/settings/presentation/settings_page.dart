import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/features/settings/data/settings_repository.dart';

/// Settings sections available in the sidebar.
enum SettingsSection { profile, api }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Form controllers
  final _loginController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _loginFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  // State
  bool _isLoading = true;
  bool _isSavingLogin = false;
  bool _isSavingPassword = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  User? _user;
  SettingsSection _selectedSection = SettingsSection.profile;

  // Bot management
  List<TelegramBotData> _bots = [];
  bool _isLoadingBots = false;
  final _botNameCtrl = TextEditingController();
  final _botTokenCtrl = TextEditingController();
  final _botChatIdCtrl = TextEditingController();
  final _botFormKey = GlobalKey<FormState>();
  bool _obscureBotToken = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _botNameCtrl.dispose();
    _botTokenCtrl.dispose();
    _botChatIdCtrl.dispose();
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
          _loginController.text = user.username;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Не удалось загрузить профиль: $e');
      }
    }
  }

  Future<void> _saveLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isSavingLogin = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final userRepository = UserRepository(dioClient.dio);

      final updated = await userRepository.updateMe(
        username: _loginController.text.trim(),
      );

      if (mounted) {
        setState(() => _user = updated);
        _showSuccess('Логин изменён');
      }
    } catch (e) {
      if (mounted) _showError('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isSavingLogin = false);
    }
  }

  Future<void> _savePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isSavingPassword = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final authRepository = AuthRepository(dioClient.dio);

      await authRepository.changePassword(
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _showSuccess('Пароль изменён');
      }
    } catch (e) {
      if (mounted) _showError('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  Future<void> _loadBots() async {
    if (_isLoadingBots) return;
    setState(() => _isLoadingBots = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final repository = SettingsRepository(dioClient.dio);
      final bots = await repository.getBots();
      if (mounted) {
        setState(() {
          _bots = bots;
          _isLoadingBots = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBots = false);
        _showError('Не удалось загрузить ботов: $e');
      }
    }
  }

  Future<void> _addBot() async {
    if (!_botFormKey.currentState!.validate()) return;

    setState(() => _isLoadingBots = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final repository = SettingsRepository(dioClient.dio);

      await repository.createBot(
        name: _botNameCtrl.text.trim(),
        botToken: _botTokenCtrl.text.trim(),
        chatId: _botChatIdCtrl.text.trim(),
      );

      _botNameCtrl.clear();
      _botTokenCtrl.clear();
      _botChatIdCtrl.clear();
      await _loadBots();
      if (mounted) _showSuccess('Бот добавлен');
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBots = false);
        _showError('Ошибка: $e');
      }
    }
  }

  Future<void> _deleteBot(String id) async {
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final repository = SettingsRepository(dioClient.dio);

      await repository.deleteBot(id);
      await _loadBots();
      if (mounted) _showSuccess('Бот удалён');
    } catch (e) {
      if (mounted) _showError('Ошибка: $e');
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade800,
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final months = [
        'янв', 'фев', 'мар', 'апр', 'май', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ResponsiveLayout(
          builder: (context, screenSize, width) {
            final isDesktop = screenSize == ScreenSize.desktop;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sidebar (desktop) / Drawer (mobile) ──
                if (isDesktop)
                  _buildDesktopSidebar(surface, textColor, subColor, isDark)
                else
                  _buildMobileDrawer(surface, textColor, subColor, isDark),

                // ── Main content ──
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(surface, textColor, subColor, isDark),
                      Expanded(
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 520),
                                    child: _selectedSection == SettingsSection.api
                                        ? _buildApiForm(textColor, subColor, isDark)
                                        : _buildProfileForm(
                                            textColor, subColor, isDark),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Desktop sidebar with settings sections.
  Widget _buildDesktopSidebar(
      Color surface, Color textColor, Color subColor, bool isDark) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.95),
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Настройки',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 8),
          // Settings nav items
          _SidebarItem(
            icon: PhosphorIconsFill.user,
            label: 'Профиль',
            isSelected: _selectedSection == SettingsSection.profile,
            isDark: isDark,
            onTap: () => setState(() => _selectedSection = SettingsSection.profile),
          ),
          _SidebarItem(
            icon: PhosphorIconsFill.robot,
            label: 'API',
            isSelected: _selectedSection == SettingsSection.api,
            isDark: isDark,
            onTap: () {
              setState(() => _selectedSection = SettingsSection.api);
              _loadBots();
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// Mobile drawer with settings sections.
  Widget _buildMobileDrawer(
      Color surface, Color textColor, Color subColor, bool isDark) {
    return const SizedBox.shrink();
  }

  /// Header with title and home button.
  Widget _buildHeader(
      Color surface, Color textColor, Color subColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      child: Row(
        children: [
          // Mobile: hamburger menu button
          IconButton(
            icon: Icon(
              PhosphorIconsFill.list,
              color: textColor,
              size: 22,
            ),
            tooltip: 'Меню настроек',
            onPressed: () => _showMobileDrawer(context, isDark, surface, textColor, subColor),
          ),
          const SizedBox(width: 4),
          Text(
            'Настройки',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Section indicator on mobile
          Text(
            _sectionLabel(),
            style: TextStyle(
              color: subColor,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(PhosphorIconsFill.house, size: 22),
            tooltip: 'На главную',
            onPressed: () => context.go('/'),
          ),
        ],
      ),
    );
  }

  void _showMobileDrawer(BuildContext context, bool isDark, Color surface,
      Color textColor, Color subColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Настройки',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              _ModalItem(
                icon: PhosphorIconsFill.user,
                label: 'Профиль',
                isSelected: _selectedSection == SettingsSection.profile,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedSection = SettingsSection.profile);
                },
              ),
              _ModalItem(
                icon: PhosphorIconsFill.robot,
                label: 'API',
                isSelected: _selectedSection == SettingsSection.api,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedSection = SettingsSection.api);
                  _loadBots();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sectionLabel() {
    switch (_selectedSection) {
      case SettingsSection.profile:
        return 'Профиль';
      case SettingsSection.api:
        return 'API';
    }
  }

  /// API / Telegram bots form content (right side).
  Widget _buildApiForm(Color textColor, Color subColor, bool isDark) {
    final theme = Theme.of(context);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.12),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section: Telegram боты ──
        Text(
          'Telegram боты',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),

        // Bot list
        if (_isLoadingBots && _bots.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_bots.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Нет добавленных ботов',
                style: TextStyle(color: subColor),
              ),
            ),
          )
        else
          ...List.generate(_bots.length, (index) {
            final bot = _bots[index];
            final maskedToken = bot.botToken.length > 5
                ? '${bot.botToken.substring(0, 5)}...'
                : '${bot.botToken}...';
            return Padding(
              padding: EdgeInsets.only(bottom: index < _bots.length - 1 ? 12 : 0),
              child: Card(
                elevation: 0,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Text('🤖', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bot.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Токен: $maskedToken',
                              style: TextStyle(
                                color: subColor,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Chat ID: ${bot.chatId}',
                              style: TextStyle(
                                color: subColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          PhosphorIconsFill.trash,
                          color: Colors.red.shade400,
                          size: 20,
                        ),
                        tooltip: 'Удалить бота',
                        onPressed: () => _deleteBot(bot.id),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),

        // ── Add bot form ──
        Text(
          'Добавить бота',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: _botFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _botNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Имя бота',
                  prefixIcon: const Icon(PhosphorIconsFill.tag, size: 20),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите имя бота';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _botTokenCtrl,
                obscureText: _obscureBotToken,
                decoration: InputDecoration(
                  labelText: 'Токен бота',
                  prefixIcon: const Icon(PhosphorIconsFill.key, size: 20),
                  border: inputBorder,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureBotToken
                          ? PhosphorIconsFill.eye
                          : PhosphorIconsFill.eyeSlash,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureBotToken = !_obscureBotToken),
                  ),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите токен бота';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _botChatIdCtrl,
                decoration: InputDecoration(
                  labelText: 'Chat ID',
                  prefixIcon: const Icon(PhosphorIconsFill.chat, size: 20),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите Chat ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _isLoadingBots ? null : _addBot,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoadingBots
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Добавить бота'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Profile form content (right side).
  Widget _buildProfileForm(Color textColor, Color subColor, bool isDark) {
    final theme = Theme.of(context);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.12),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section: Login ──
        Text(
          'Логин',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: _loginFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _loginController,
                decoration: InputDecoration(
                  labelText: 'Имя пользователя',
                  prefixIcon: const Icon(PhosphorIconsFill.user, size: 20),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saveLogin(),
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
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _isSavingLogin ? null : _saveLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSavingLogin
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),
        Divider(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 24),

        // ── Section: Password ──
        Text(
          'Пароль',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _oldPasswordController,
                obscureText: _obscureOld,
                decoration: InputDecoration(
                  labelText: 'Текущий пароль',
                  prefixIcon: const Icon(PhosphorIconsFill.lock, size: 20),
                  border: inputBorder,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureOld
                          ? PhosphorIconsFill.eye
                          : PhosphorIconsFill.eyeSlash,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureOld = !_obscureOld),
                  ),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите текущий пароль';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'Новый пароль',
                  prefixIcon: const Icon(PhosphorIconsFill.lockOpen, size: 20),
                  border: inputBorder,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew
                          ? PhosphorIconsFill.eye
                          : PhosphorIconsFill.eyeSlash,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите новый пароль';
                  }
                  if (value.length < 6) {
                    return 'Минимум 6 символов';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Подтвердите новый пароль',
                  prefixIcon:
                      const Icon(PhosphorIconsFill.checkCircle, size: 20),
                  border: inputBorder,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? PhosphorIconsFill.eye
                          : PhosphorIconsFill.eyeSlash,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _savePassword(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Подтвердите новый пароль';
                  }
                  if (value != _newPasswordController.text) {
                    return 'Пароли не совпадают';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _isSavingPassword ? null : _savePassword,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSavingPassword
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Изменить пароль'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),
        Divider(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 24),

        // ── Section: Account info (read-only) ──
        Text(
          'Информация об аккаунте',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),
        _InfoRow(label: 'Email', value: _user?.email ?? '—'),
        const SizedBox(height: 12),
        _InfoRow(
          label: 'Дата регистрации',
          value: _formatDate(_user?.createdAt),
        ),
      ],
    );
  }
}

/// A sidebar menu item for settings sections.
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accentColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? AppTheme.accentColor
                      : (isDark
                          ? AppTheme.textPrimary.withValues(alpha: 0.7)
                          : AppTheme.lightTextPrimary.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? AppTheme.accentColor
                        : (isDark
                            ? AppTheme.textPrimary
                            : AppTheme.lightTextPrimary),
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppTheme.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal bottom sheet item for mobile.
class _ModalItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ModalItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: isSelected
            ? AppTheme.accentColor
            : (isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppTheme.accentColor
              : (isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: isSelected
          ? Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppTheme.accentColor,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Read-only info row (email, registration date).
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
