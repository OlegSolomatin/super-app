import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/features/admin/data/admin_repository.dart';
import 'package:app/features/admin/models/deepseek_balance.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/pf_card.dart';

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
      if (mounted) setState(() { _balance = balance; _error = null; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'DeepSeek API',
      showBackButton: true,
      currentPath: '/admin/deepseek',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: PfColors.accentAdmin))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadBalance,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(PfSpacing.lg),
                    children: [
                      if (_balance != null) _buildBalanceContent(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PfSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(PhosphorIconsFill.warning, size: 56, color: PfColors.destructive),
            const SizedBox(height: PfSpacing.md),
            Text('Не удалось получить баланс', style: PfTypography.titleMd.copyWith(color: PfColors.mutedForeground), textAlign: TextAlign.center),
            const SizedBox(height: PfSpacing.xs),
            Text(_error ?? '', style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground), textAlign: TextAlign.center),
            const SizedBox(height: PfSpacing.lg),
            PfCard(
              onTap: _loadBalance,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PhosphorIcon(PhosphorIconsFill.arrowsClockwise, size: 16, color: PfColors.accentAdmin),
                  const SizedBox(width: PfSpacing.xs),
                  Text('Повторить', style: PfTypography.button.copyWith(color: PfColors.accentAdmin)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceContent() {
    final balance = _balance!;
    final mainInfo = balance.balanceInfos.isNotEmpty ? balance.balanceInfos.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status header — stat-callout
        PfCard(
          padding: const EdgeInsets.all(PfSpacing.xl),
          child: Column(
            children: [
              // Status circle icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: balance.isAvailable
                      ? PfColors.success.withValues(alpha: 0.15)
                      : PfColors.destructive.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: PhosphorIcon(
                    balance.isAvailable ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.xCircle,
                    size: 32,
                    color: balance.isAvailable ? PfColors.success : PfColors.destructive,
                  ),
                ),
              ),
              const SizedBox(height: PfSpacing.md),
              Text(
                balance.isAvailable ? 'API доступен' : 'API недоступен',
                style: PfTypography.titleLg.copyWith(color: PfColors.foreground),
              ),
            ],
          ),
        ),
        const SizedBox(height: PfSpacing.lg),

        // Balance cards — stat-callout style
        if (mainInfo != null) ...[
          _BalanceCard(
            label: 'Общий баланс',
            amount: mainInfo.totalBalance,
            currency: mainInfo.currency,
            icon: PhosphorIconsFill.wallet,
            color: PfColors.accentAdmin,
          ),
          const SizedBox(height: PfSpacing.sm),
          _BalanceCard(
            label: 'Пополнено',
            amount: mainInfo.toppedUpBalance,
            currency: mainInfo.currency,
            icon: PhosphorIconsFill.arrowCircleUp,
            color: PfColors.success,
          ),
          const SizedBox(height: PfSpacing.sm),
          _BalanceCard(
            label: 'Бесплатный грант',
            amount: mainInfo.grantedBalance,
            currency: mainInfo.currency,
            icon: PhosphorIconsFill.gift,
            color: const Color(0xFF81C784),
          ),
        ],

        const SizedBox(height: PfSpacing.lg),

        // Usage hint
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(PfSpacing.md),
          decoration: BoxDecoration(
            color: PfColors.accentAdmin.withValues(alpha: 0.08),
            borderRadius: PfRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              const PhosphorIcon(PhosphorIconsFill.info, size: 20, color: PfColors.accentAdmin),
              const SizedBox(width: PfSpacing.sm),
              Expanded(
                child: Text(
                  'Баланс обновляется раз в минуту. Тяни вниз для принудительного обновления.',
                  style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Balance Card (stat-callout style) ─────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final PhosphorIconData icon;
  final Color color;

  const _BalanceCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return PfCard(
      padding: const EdgeInsets.all(PfSpacing.lg),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: PfRadius.borderRadiusMd,
            ),
            child: Center(
              child: PhosphorIcon(icon, size: 22, color: color),
            ),
          ),
          const SizedBox(width: PfSpacing.md),
          // Label + amount
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: PfTypography.caption.copyWith(color: PfColors.mutedForeground)),
                const SizedBox(height: PfSpacing.xs),
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: PfTypography.number.copyWith(
                    color: PfColors.foreground,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Currency
          Text(currency, style: PfTypography.bodyMd.copyWith(color: PfColors.mutedForeground)),
        ],
      ),
    );
  }
}
