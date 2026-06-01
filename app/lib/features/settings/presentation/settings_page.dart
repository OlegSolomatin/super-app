import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        backgroundColor: surface.withValues(alpha: 0.85),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedContent(
          maxWidth: 600,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
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
