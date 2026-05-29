import 'package:go_router/go_router.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/features/auth/presentation/login_page.dart';
import 'package:app/features/auth/presentation/register_page.dart';
import 'package:app/features/home/presentation/home_page.dart';
import 'package:app/features/trading/presentation/wizard_page.dart';
import 'package:app/features/admin/presentation/agents_page.dart';

class AppRouter {
  final SecureStorage _storage;

  AppRouter(this._storage);

  late final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final isLoggedIn = await _isAuthenticated();
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }
      if (isLoggedIn && isAuthRoute) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/admin/agents',
        builder: (context, state) => const AdminAgentsPage(),
      ),
      GoRoute(
        path: '/trading/wizard',
        builder: (context, state) => const TradingWizardPage(),
      ),
    ],
  );

  Future<bool> _isAuthenticated() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
