import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/shared/tokens/pf_colors.dart';

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
    debugPrint('[REGISTER ERROR] $message');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      PhosphorIconsFill.userPlus,
                      size: 30,
                      color: PfColors.accentLogin,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Создать аккаунт',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF181A20),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Зарегистрируйтесь в Super App',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 32),

                // ── Registration form ──
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
                        _buildField(
                          controller: _emailController,
                          label: 'Email',
                          icon: PhosphorIconsFill.envelope,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Введите email';
                            if (!v.contains('@')) return 'Некорректный email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _usernameController,
                          label: 'Имя пользователя',
                          icon: PhosphorIconsFill.user,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Введите имя пользователя';
                            if (v.trim().length < 3) return 'Минимум 3 символа';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildPasswordField(
                          controller: _passwordController,
                          label: 'Пароль',
                          obscure: _obscurePassword,
                          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        const SizedBox(height: 14),
                        _buildPasswordField(
                          controller: _confirmPasswordController,
                          label: 'Подтвердите пароль',
                          obscure: _obscureConfirm,
                          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          isConfirm: true,
                        ),
                        const SizedBox(height: 20),
                        // Register button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PfColors.accentLogin,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              disabledBackgroundColor: const Color(0xFF9CA3AF),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Зарегистрироваться', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Login link ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Уже есть аккаунт? ', style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        'Войти',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: PfColors.accentLogin),
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
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required PhosphorIconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 15, color: Color(0xFF181A20)),
      decoration: _inputDecoration(label, icon),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    bool isConfirm = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: isConfirm ? TextInputAction.done : TextInputAction.next,
      style: const TextStyle(fontSize: 15, color: Color(0xFF181A20)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        prefixIcon: PhosphorIcon(PhosphorIconsFill.lock, size: 18, color: const Color(0xFF9CA3AF)),
        suffixIcon: IconButton(
          icon: PhosphorIcon(
            obscure ? PhosphorIconsFill.eyeSlash : PhosphorIconsFill.eye,
            size: 18,
            color: const Color(0xFF9CA3AF),
          ),
          onPressed: onToggle,
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
          borderSide: BorderSide(color: PfColors.accentLogin, width: 1.5),
        ),
      ),
      onFieldSubmitted: isConfirm ? (_) => _register() : null,
      validator: (v) {
        if (v == null || v.isEmpty) return isConfirm ? 'Подтвердите пароль' : 'Введите пароль';
        if (!isConfirm && v.length < 6) return 'Минимум 6 символов';
        if (isConfirm && v != _passwordController.text) return 'Пароли не совпадают';
        return null;
      },
    );
  }

  InputDecoration _inputDecoration(String label, PhosphorIconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
      prefixIcon: PhosphorIcon(icon, size: 18, color: const Color(0xFF9CA3AF)),
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
        borderSide: BorderSide(color: PfColors.accentLogin, width: 1.5),
      ),
    );
  }
}
