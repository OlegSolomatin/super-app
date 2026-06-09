import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _usernameFocusNode = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isTablet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final w = MediaQuery.of(context).size.width;
      _isTablet = w >= 600 && w < 1200;
      if (!_isTablet) {
        _usernameFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final authRepository = AuthRepository(dioClient.dio);
      final tokens = await authRepository.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      await storage.saveAccessToken(tokens.accessToken);
      await storage.saveRefreshToken(tokens.refreshToken);
      if (mounted) context.go('/');
    } catch (e) {
      _logError(e);
      if (mounted) {
        String message;
        if (e is DioException) {
          if (e.response?.data is Map) {
            final data = e.response!.data as Map;
            message = data.containsKey('detail')
                ? data['detail'].toString()
                : 'Ошибка сервера (${e.response?.statusCode})';
          } else if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError) {
            message = 'Сервер не отвечает. Проверьте соединение.';
          } else if (e.type == DioExceptionType.badResponse) {
            message = 'Ошибка сервера (${e.response?.statusCode})';
          } else {
            message = 'Не удалось войти. Попробуйте позже.';
          }
        } else {
          message = 'Неизвестная ошибка';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: PfColors.destructive,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logError(Object e) {
    String message;
    if (e is DioException) {
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data.containsKey('detail')) message = data['detail'].toString();
        else message = 'Статус: ${e.response?.statusCode}';
      } else if (e.response?.data is String) {
        message = 'Статус: ${e.response?.statusCode}, тело: ${e.response?.data}';
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        message = 'Таймаут соединения';
      } else {
        message = e.toString();
      }
    } else {
      message = e.toString();
    }
    debugPrint('[LOGIN ERROR] $message');
  }

  void _showThemeSheet() {
    final provider = context.read<ThemeProvider>();
    final pc = PfColors.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: pc.cardC,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: pc.borderC, width: 1),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PfSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: pc.mutedForegroundC,
                  borderRadius: PfRadius.borderRadiusPill,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Тема оформления',
                style: PfTypography.titleLg.copyWith(color: pc.foregroundC),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ThemeOption(
                    icon: PhosphorIconsFill.moon,
                    label: 'Тёмная',
                    active: provider.mode == ThemeModePreference.dark,
                    color: PfColors.accentLogin,
                    pc: pc,
                    onTap: () {
                      provider.setMode(ThemeModePreference.dark);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    icon: PhosphorIconsFill.desktop,
                    label: 'Системная',
                    active: provider.mode == ThemeModePreference.system,
                    color: PfColors.accentLogin,
                    pc: pc,
                    onTap: () {
                      provider.setMode(ThemeModePreference.system);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    icon: PhosphorIconsFill.sun,
                    label: 'Светлая',
                    active: provider.mode == ThemeModePreference.light,
                    color: PfColors.accentLogin,
                    pc: pc,
                    onTap: () {
                      provider.setMode(ThemeModePreference.light);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);

    return Scaffold(
      backgroundColor: pc.backgroundC,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Centered form ──
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Header ──
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: PfColors.accentLogin.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(
                          child: PhosphorIcon(
                            PhosphorIconsFill.lockKey,
                            size: 30,
                            color: PfColors.accentLogin,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Super App',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: pc.foregroundC,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Войдите в свой аккаунт',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: pc.mutedForegroundC,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Login form ──
                      Container(
                        decoration: BoxDecoration(
                          color: pc.cardC,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: pc.borderC),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Username
                              TextFormField(
                                controller: _usernameController,
                                focusNode: _usernameFocusNode,
                                textCapitalization: TextCapitalization.none,
                                textInputAction: TextInputAction.next,
                                style: TextStyle(fontSize: 15, color: pc.foregroundC),
                                decoration: InputDecoration(
                                  labelText: 'Имя пользователя',
                                  labelStyle: TextStyle(fontSize: 14, color: pc.mutedForegroundC),
                                  prefixIcon: PhosphorIcon(
                                    PhosphorIconsFill.user,
                                    size: 18,
                                    color: pc.mutedForegroundC,
                                  ),
                                  filled: true,
                                  fillColor: pc.surfaceC,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: pc.borderC),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: pc.borderC),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: PfColors.accentLogin,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите имя пользователя' : null,
                                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                              ),
                              const SizedBox(height: 14),
                              // Password
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                style: TextStyle(fontSize: 15, color: pc.foregroundC),
                                decoration: InputDecoration(
                                  labelText: 'Пароль',
                                  labelStyle: TextStyle(fontSize: 14, color: pc.mutedForegroundC),
                                  prefixIcon: PhosphorIcon(
                                    PhosphorIconsFill.lock,
                                    size: 18,
                                    color: pc.mutedForegroundC,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: PhosphorIcon(
                                      _obscurePassword ? PhosphorIconsFill.eyeSlash : PhosphorIconsFill.eye,
                                      size: 18,
                                      color: pc.mutedForegroundC,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  filled: true,
                                  fillColor: pc.surfaceC,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: pc.borderC),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: pc.borderC),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: PfColors.accentLogin,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'Введите пароль' : null,
                                onFieldSubmitted: (_) => _login(),
                              ),
                              const SizedBox(height: 20),
                              // Login button
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: PfColors.accentLogin,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    disabledBackgroundColor: pc.mutedForegroundC,
                                  ),
                                  child: _isLoading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: pc.foregroundC,
                                          ),
                                        )
                                      : Text(
                                          'Войти',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Register link ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Нет аккаунта? ',
                            style: TextStyle(
                              fontSize: 14,
                              color: pc.mutedForegroundC,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.push('/register'),
                            child: Text(
                              'Зарегистрироваться',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: PfColors.accentLogin,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            // ── Theme toggle top-right ──
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: PhosphorIcon(
                  context.watch<ThemeProvider>().mode == ThemeModePreference.light
                      ? PhosphorIconsFill.sun
                      : context.watch<ThemeProvider>().mode == ThemeModePreference.dark
                          ? PhosphorIconsFill.moon
                          : PhosphorIconsFill.desktop,
                  size: 20,
                  color: pc.mutedForegroundC,
                ),
                onPressed: _showThemeSheet,
                tooltip: 'Тема оформления',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Theme Option widget ──────────────────────────────────────────────────────
class _ThemeOption extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final bool active;
  final Color color;
  final PfColors pc;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    required this.pc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.4) : pc.borderC,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 24, color: active ? color : pc.mutedForegroundC),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? color : pc.mutedForegroundC,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
