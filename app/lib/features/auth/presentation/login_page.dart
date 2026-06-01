import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/auth/data/auth_repository.dart';
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

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка входа: ${_extractErrorMessage(e)}'),
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

  String _extractErrorMessage(Object e) {
    if (e is DioException && e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ResponsiveLayout(
            maxContentWidth: 480,
            builder: (context, screenSize, width) {
              final isDesktop = screenSize == ScreenSize.desktop;

              final formCard = SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 0 : 24,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: isDesktop
                      ? const EdgeInsets.all(40)
                      : EdgeInsets.zero,
                  decoration: isDesktop
                      ? BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppTheme.surfaceColor
                              : AppTheme.lightSurfaceColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isDesktop
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 40,
                                    offset: const Offset(0, 10),
                                  ),
                                ]
                              : null,
                        )
                      : null,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.rocket_launch,
                          size: isDesktop ? 48 : 64,
                          color: AppTheme.accentColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Super App',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.headlineLarge?.copyWith(
                                    fontSize: isDesktop ? 24 : 28,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Войдите в свой аккаунт',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: isDesktop ? 14 : 16,
                          ),
                        ),
                        SizedBox(height: isDesktop ? 32 : 40),
                        TextFormField(
                          controller: _usernameController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.none,
                          textInputAction: TextInputAction.next,
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
                          onFieldSubmitted: (_) {
                            FocusScope.of(context).nextFocus();
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(
                                    () => _obscurePassword = !_obscurePassword);
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Введите пароль';
                            }
                            if (value.length < 6) {
                              return 'Пароль должен быть минимум 6 символов';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Войти'),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => context.push('/register'),
                          child: const Text(
                              'Нет аккаунта? Зарегистрироваться'),
                        ),
                      ],
                    ),
                  ),
                ),
              );

              if (isDesktop) {
                return formCard;
              }
              return formCard;
            },
          ),
        ),
      ),
    );
  }
}
