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
  bool _isLoading = false;
  bool _obscurePassword = true;
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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

    showModalBottomSheet(
      context: context,
      backgroundColor: PfColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: PfColors.mutedForeground,
                  borderRadius: PfRadius.borderRadiusPill,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Тема оформления',
                style: PfTypography.titleLg.copyWith(color: PfColors.foreground),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF181A20),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Войдите в свой аккаунт',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Login form ──
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
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
                                textCapitalization: TextCapitalization.none,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(fontSize: 15, color: Color(0xFF181A20)),
                                decoration: InputDecoration(
                                  labelText: 'Имя пользователя',
                                  labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                                  prefixIcon: const PhosphorIcon(
                                    PhosphorIconsFill.user,
                                    size: 18,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF9FAFB),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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
                                style: const TextStyle(fontSize: 15, color: Color(0xFF181A20)),
                                decoration: InputDecoration(
                                  labelText: 'Пароль',
                                  labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                                  prefixIcon: const PhosphorIcon(
                                    PhosphorIconsFill.lock,
                                    size: 18,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: PhosphorIcon(
                                      _obscurePassword ? PhosphorIconsFill.eyeSlash : PhosphorIconsFill.eye,
                                      size: 18,
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF9FAFB),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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
                                    disabledBackgroundColor: const Color(0xFF9CA3AF),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Войти',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
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
                              color: const Color(0xFF6B7280),
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
                  color: const Color(0xFF6B7280),
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
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
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
            color: active ? color.withValues(alpha: 0.4) : const Color(0xFFE5E7EB),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 24, color: active ? color : const Color(0xFF6B7280)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? color : const Color(0xFF6B7280),
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
