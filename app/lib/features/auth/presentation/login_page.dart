import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_button.dart';

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка входа: ${_extractErrorMessage(e)}'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _extractErrorMessage(Object e) {
    if (e is DioException && e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map && data.containsKey('detail')) return data['detail'].toString();
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PfColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              child: PfCard(
                padding: const EdgeInsets.all(PfSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Icon
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: PfColors.accentLogin.withValues(alpha: 0.1),
                            borderRadius: PfRadius.borderRadiusXl,
                          ),
                          child: const Center(
                            child: PhosphorIcon(
                              PhosphorIconsFill.rocketLaunch,
                              size: 28,
                              color: PfColors.accentLogin,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: PfSpacing.lg),
                      // Title
                      Text(
                        'Super App',
                        textAlign: TextAlign.center,
                        style: PfTypography.displayMd.copyWith(
                          color: PfColors.foregroundLight,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: PfSpacing.xs),
                      Text(
                        'Войдите в свой аккаунт',
                        textAlign: TextAlign.center,
                        style: PfTypography.bodyMd.copyWith(
                          color: PfColors.mutedForegroundLight,
                        ),
                      ),
                      const SizedBox(height: PfSpacing.xl),
                      // Username
                      TextFormField(
                        controller: _usernameController,
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Имя пользователя',
                          prefixIcon: const PhosphorIcon(
                            PhosphorIconsFill.user,
                            size: 18,
                          ),
                          filled: true,
                          fillColor: PfColors.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: PfRadius.borderRadiusMd,
                            borderSide: BorderSide(color: PfColors.borderLight),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Введите имя пользователя';
                          if (value.trim().length < 2) return 'Минимум 2 символа';
                          return null;
                        },
                        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: PfSpacing.md),
                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const PhosphorIcon(
                            PhosphorIconsFill.lock,
                            size: 18,
                          ),
                          suffixIcon: IconButton(
                            icon: PhosphorIcon(
                              _obscurePassword
                                  ? PhosphorIconsFill.eyeSlash
                                  : PhosphorIconsFill.eye,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: PfColors.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: PfRadius.borderRadiusMd,
                            borderSide: BorderSide(color: PfColors.borderLight),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Введите пароль';
                          if (value.length < 6) return 'Пароль должен быть минимум 6 символов';
                          return null;
                        },
                        onFieldSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: PfSpacing.lg),
                      // Submit
                      PfButton(
                        variant: 'primary',
                        size: 'lg',
                        label: 'Войти',
                        isLoading: _isLoading,
                        expanded: true,
                        onPressed: _isLoading ? null : _login,
                      ),
                      const SizedBox(height: PfSpacing.md),
                      // Register link
                      Center(
                        child: TextButton(
                          onPressed: () => context.push('/register'),
                          child: Text(
                            'Нет аккаунта? Зарегистрироваться',
                            style: PfTypography.bodySm.copyWith(
                              color: PfColors.accentLogin,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
