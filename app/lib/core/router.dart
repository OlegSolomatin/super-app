import 'package:go_router/go_router.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/auth/presentation/login_page.dart';
import 'package:app/features/auth/presentation/register_page.dart';
import 'package:app/features/home/presentation/home_page.dart';
import 'package:app/features/trading/presentation/trading_page.dart';
import 'package:app/features/trading/presentation/wizard_page.dart';
import 'package:app/features/trading/presentation/orderbook_wizard_page.dart';
import 'package:app/features/trading/presentation/orderbook_run_detail_page.dart';
import 'package:app/features/trading/presentation/run_detail_page.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/features/admin/presentation/agents_page.dart';
import 'package:app/features/admin/presentation/deepseek_balance_page.dart';
import 'package:app/features/admin/presentation/brain_page.dart';
import 'package:app/features/settings/presentation/settings_page.dart';

class AppRouter {
  final SecureStorage _storage;
  late final DioClient _dioClient;
  late final TradingRepository _tradingRepository;

  AppRouter(this._storage) {
    _dioClient = DioClient(_storage);
    _tradingRepository = TradingRepository(_dioClient);
  }

  late final GoRouter router = GoRouter(
    redirect: (context, state) async {
      final isLoggedIn = await _isAuthenticated();
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      final isPublicRoute = state.matchedLocation == '/';

      if (!isLoggedIn && !isAuthRoute && !isPublicRoute) {
        return '/';
      }
      if (isLoggedIn && isAuthRoute) {
        return '/';
      }
      return null;
    },
    initialLocation: '/',
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
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/admin/agents',
        builder: (context, state) => const AdminAgentsPage(),
      ),
      GoRoute(
        path: '/admin/deepseek-balance',
        builder: (context, state) => const DeepSeekBalancePage(),
      ),
      GoRoute(
        path: '/admin/brain',
        builder: (context, state) => const BrainPage(),
      ),
      GoRoute(
        path: '/trading',
        builder: (context, state) => TradingPage(
          repository: _tradingRepository,
        ),
      ),
      GoRoute(
        path: '/trading/wizard',
        builder: (context, state) => TradingWizardPage(
          repository: _tradingRepository,
        ),
      ),
      GoRoute(
        path: '/trading/orderbook-wizard',
        builder: (context, state) => OrderBookWizardPage(
          repository: _tradingRepository,
        ),
      ),
      GoRoute(
        path: '/trading/run/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TradingRunDetailPage(
            runId: id,
            repository: _tradingRepository,
          );
        },
      ),
      GoRoute(
        path: '/trading/ob-run/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return OrderBookRunDetailPage(
            runId: id,
            repository: _tradingRepository,
          );
        },
      ),
    ],
  );

  Future<bool> _isAuthenticated() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
