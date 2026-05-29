import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/home/data/user_repository.dart';
import 'package:app/models/user.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
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
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        title: const Text('Super App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.accentColor, Color(0xFF9B7CFF)],
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
                    const SizedBox(height: 24),
                    Text(
                      'Сервисы',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    _buildDashboardGrid(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDashboardGrid() {
    final cards = [
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
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return _DashboardCard(data: card);
      },
    );
  }
}

class _DashboardCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _DashboardCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}

class _DashboardCard extends StatelessWidget {
  final _DashboardCardData data;

  const _DashboardCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${data.title} — скоро'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  data.icon,
                  color: data.color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.subtitle,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
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
    );
  }
}
