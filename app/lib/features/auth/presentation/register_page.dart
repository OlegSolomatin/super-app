import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_button.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final authRepository = AuthRepository(dioClient.dio);
      final tokens = await authRepository.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        username: _usernameController.text.trim(),
      );
      await storage.saveAccessToken(tokens.accessToken);
      await storage.saveRefreshToken(tokens.refreshToken);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка регистрации: ${_extractErrorMessage(e)}'),
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
                              PhosphorIconsFill.userPlus,
                              size: 28,
                              color: PfColors.accentLogin,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: PfSpacing.lg),
                      // Title
                      Text(
                        'Создать аккаунт',
                        textAlign: TextAlign.center,
                        style: PfTypography.displayMd.copyWith(
                          color: PfColors.foregroundLight,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: PfSpacing.xs),
                      Text(
                        'Зарегистрируйтесь в Super App',
                        textAlign: TextAlign.center,
                        style: PfTypography.bodyMd.copyWith(
                          color: PfColors.mutedForegroundLight,
                        ),
                      ),
                      const SizedBox(height: PfSpacing.xl),
                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const PhosphorIcon(
                            PhosphorIconsFill.envelope,
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
                          if (value == null || value.trim().isEmpty) return 'Введите email';
                          if (!value.contains('@')) return 'Некорректный email';
                          return null;
                        },
                      ),
                      const SizedBox(height: PfSpacing.md),
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
                          if (value.trim().length < 3) return 'Минимум 3 символа';
                          return null;
                        },
                      ),
                      const SizedBox(height: PfSpacing.md),
                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
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
                      ),
                      const SizedBox(height: PfSpacing.md),
                      // Confirm password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Подтвердите пароль',
                          prefixIcon: const PhosphorIcon(
                            PhosphorIconsFill.lock,
                            size: 18,
                          ),
                          suffixIcon: IconButton(
                            icon: PhosphorIcon(
                              _obscureConfirm
                                  ? PhosphorIconsFill.eyeSlash
                                  : PhosphorIconsFill.eye,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          filled: true,
                          fillColor: PfColors.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: PfRadius.borderRadiusMd,
                            borderSide: BorderSide(color: PfColors.borderLight),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Подтвердите пароль';
                          if (value != _passwordController.text) return 'Пароли не совпадают';
                          return null;
                        },
                        onFieldSubmitted: (_) => _register(),
                      ),
                      const SizedBox(height: PfSpacing.lg),
                      // Submit
                      PfButton(
                        variant: 'primary',
                        size: 'lg',
                        label: 'Зарегистрироваться',
                        isLoading: _isLoading,
                        expanded: true,
                        onPressed: _isLoading ? null : _register,
                      ),
                      const SizedBox(height: PfSpacing.md),
                      // Login link
                      Center(
                        child: TextButton(
                          onPressed: () => context.go('/login'),
                          child: Text(
                            'Уже есть аккаунт? Войти',
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
