import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/features/admin/data/admin_repository.dart';
import 'package:app/features/admin/models/deepseek_balance.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

class DeepSeekBalancePage extends StatefulWidget {
  const DeepSeekBalancePage({super.key});

  @override
  State<DeepSeekBalancePage> createState() => _DeepSeekBalancePageState();
}

class _DeepSeekBalancePageState extends State<DeepSeekBalancePage> {
  DeepseekBalance? _balance;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    setState(() => _isLoading = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final repo = AdminRepository(dioClient.dio);
      final balance = await repo.getDeepseekBalance();
      if (mounted) {
        setState(() {
          _balance = balance;
          _error = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;
    final textColor =
        isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('DeepSeek API'),
        backgroundColor: isDark
            ? AppTheme.bgColor.withValues(alpha: 0.85)
            : AppTheme.lightSurfaceColor.withValues(alpha: 0.85),
        elevation: 0,
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsFill.caretLeft),
          onPressed: () => context.go('/'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadBalance,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedContent(
                      child: _balance != null
                          ? _buildBalanceContent(isDark, textColor, subColor, surface)
                          : const Center(child: Text('Нет данных')),
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(
              PhosphorIconsFill.warning,
              size: 56,
              color: Color(0xFFE53935),
            ),
            const SizedBox(height: 16),
            Text(
              'Не удалось получить баланс',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBalance,
              icon: const PhosphorIcon(PhosphorIconsFill.arrowsClockwise),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceContent(
    bool isDark,
    Color textColor,
    Color subColor,
    Color surface,
  ) {
    final balance = _balance!;
    final mainInfo = balance.balanceInfos.isNotEmpty
        ? balance.balanceInfos.first
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: balance.isAvailable
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
                  : const Color(0xFFE53935).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: balance.isAvailable
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                      : const Color(0xFFE53935).withValues(alpha: 0.15),
                ),
                child: Center(
                  child: PhosphorIcon(
                    balance.isAvailable
                        ? PhosphorIconsFill.checkCircle
                        : PhosphorIconsFill.xCircle,
                    size: 32,
                    color: balance.isAvailable
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFE53935),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                balance.isAvailable ? 'API доступен' : 'API недоступен',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Balance cards
        if (mainInfo != null) ...[
          _BalanceCard(
            label: 'Общий баланс',
            amount: mainInfo.totalBalance,
            currency: mainInfo.currency,
            color: const Color(0xFF7C5CFC),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _BalanceCard(
            label: 'Пополнено',
            amount: mainInfo.toppedUpBalance,
            currency: mainInfo.currency,
            color: const Color(0xFF4FC3F7),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _BalanceCard(
            label: 'Бесплатный грант',
            amount: mainInfo.grantedBalance,
            currency: mainInfo.currency,
            color: const Color(0xFF81C784),
            isDark: isDark,
          ),
        ],

        const SizedBox(height: 24),

        // Usage hint
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsFill.info,
                size: 20,
                color: AppTheme.accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Баланс обновляется раз в минуту. '
                  'Тяни вниз для принудительного обновления.',
                  style: TextStyle(
                    color: subColor,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Balance Card ────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final Color color;
  final bool isDark;

  const _BalanceCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppTheme.cardColor : AppTheme.lightCardColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: PhosphorIcon(
                PhosphorIconsFill.coin,
                size: 22,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.lightTextSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textPrimary
                        : AppTheme.lightTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            currency,
            style: TextStyle(
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.lightTextSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
