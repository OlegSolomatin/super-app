import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/features/admin/data/admin_repository.dart';
import 'package:app/features/admin/models/agent_status.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_badge.dart';
import 'package:app/shared/widgets/pf_divider.dart';

const double _maxTokens = 100000.0;

class AdminAgentsPage extends StatefulWidget {
  const AdminAgentsPage({super.key});

  @override
  State<AdminAgentsPage> createState() => _AdminAgentsPageState();
}

class _AdminAgentsPageState extends State<AdminAgentsPage>
    with TickerProviderStateMixin {
  List<AgentStatus>? _agents;
  String? _sessionTask;
  bool _isLoading = true;
  String? _error;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadAgentStatuses();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadAgentStatuses() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final repository = AdminRepository(dioClient.dio);
      final agents = await repository.getAgentStatuses();
      agents.sort((a, b) {
        final aPos = int.tryParse(a.position) ?? 0;
        final bPos = int.tryParse(b.position) ?? 0;
        return aPos.compareTo(bPos);
      });
      String? sessionTask;
      if (agents.isNotEmpty) {
        final working = agents.where((a) => a.isWorking).toList();
        if (working.isNotEmpty) sessionTask = working.first.currentTask;
      }
      if (mounted) setState(() { _agents = agents; _sessionTask = sessionTask; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Мониторинг агентов',
      currentPath: '/admin/agents',
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: PfColors.accentAdmin));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PhosphorIcon(PhosphorIconsFill.warning, size: 48, color: PfColors.destructive),
            const SizedBox(height: PfSpacing.md),
            Text('Ошибка загрузки', style: PfTypography.titleMd.copyWith(color: PfColors.mutedForeground)),
            const SizedBox(height: PfSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PfSpacing.xl),
              child: Text(_error!, style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground), textAlign: TextAlign.center),
            ),
            const SizedBox(height: PfSpacing.lg),
            PfCard(
              variant: 'default',
              onTap: _loadAgentStatuses,
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
      );
    }

    final agents = _agents ?? [];

    return RefreshIndicator(
      onRefresh: _loadAgentStatuses,
      color: PfColors.accentAdmin,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(PfSpacing.md),
        children: [
          // Session task
          if (_sessionTask != null && _sessionTask!.isNotEmpty) ...[
            _buildSessionSection(),
            const SizedBox(height: PfSpacing.md),
          ],
          // Agent count header
          Padding(
            padding: const EdgeInsets.only(bottom: PfSpacing.md),
            child: Row(
              children: [
                Text(
                  'Агенты',
                  style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
                ),
                const SizedBox(width: PfSpacing.sm),
                PfBadge(variant: 'info', label: '${agents.length}'),
              ],
            ),
          ),
          // Agent cards
          ...agents.map((agent) => Padding(
            padding: const EdgeInsets.only(bottom: PfSpacing.sm),
            child: _AgentCard(agent: agent, pulseAnimation: _pulseAnimation),
          )),
        ],
      ),
    );
  }

  Widget _buildSessionSection() {
    return PfCard(
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFD700),
                ),
              ),
              const SizedBox(width: PfSpacing.sm),
              Text('Сессия', style: PfTypography.titleMd.copyWith(color: PfColors.foreground)),
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          Text(
            _sessionTask!,
            style: PfTypography.bodyMd.copyWith(
              color: PfColors.mutedForeground,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Agent Card ────────────────────────────────────────────────────────

class _AgentCard extends StatelessWidget {
  final AgentStatus agent;
  final Animation<double> pulseAnimation;

  const _AgentCard({required this.agent, required this.pulseAnimation});

  Color get _statusColor {
    if (agent.isError) return PfColors.destructive;
    if (agent.isWorking) return const Color(0xFFFFD700);
    return PfColors.success;
  }

  String get _statusLabel {
    if (agent.isError) return 'Ошибка';
    if (agent.isWorking) return 'Работает';
    return 'Ожидает';
  }

  @override
  Widget build(BuildContext context) {
    return PfCard(
      variant: 'default',
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: status dot + name + role + status badge
          Row(
            children: [
              // Pulse/static status dot
              agent.isWorking
                  ? AnimatedBuilder(
                      animation: pulseAnimation,
                      builder: (context, child) => Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor.withValues(alpha: pulseAnimation.value),
                          boxShadow: [
                            BoxShadow(
                              color: _statusColor.withValues(alpha: pulseAnimation.value * 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusColor,
                      ),
                    ),
              const SizedBox(width: PfSpacing.sm),
              // Name and role
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.name, style: PfTypography.titleMd.copyWith(color: PfColors.foreground)),
                    const SizedBox(height: 2),
                    Text(agent.role, style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground)),
                  ],
                ),
              ),
              PfBadge(
                variant: agent.isError ? 'destructive' : (agent.isWorking ? 'warning' : 'success'),
                label: _statusLabel,
                size: 'sm',
              ),
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          // Model + Provider
          Row(
            children: [
              const PhosphorIcon(PhosphorIconsFill.cpu, size: 14, color: PfColors.mutedForeground),
              const SizedBox(width: PfSpacing.xs),
              Text(
                '${agent.model} · ${agent.provider}',
                style: PfTypography.caption.copyWith(color: PfColors.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          // Token progress
          _buildTokenProgress(),
          // Cost
          if (agent.costUsd > 0) ...[
            const SizedBox(height: PfSpacing.xs),
            Row(
              children: [
                const PhosphorIcon(PhosphorIconsFill.coin, size: 14, color: PfColors.mutedForeground),
                const SizedBox(width: PfSpacing.xs),
                Text(
                  '\$${agent.costUsd.toStringAsFixed(4)}',
                  style: PfTypography.caption.copyWith(color: PfColors.success, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
          // Working task
          if (agent.isWorking && agent.currentTask.isNotEmpty) ...[
            const SizedBox(height: PfSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: PfSpacing.sm, vertical: PfSpacing.sm),
              decoration: BoxDecoration(
                color: PfColors.accentAdmin.withValues(alpha: 0.1),
                borderRadius: PfRadius.borderRadiusMd,
                border: Border.all(color: PfColors.accentAdmin.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text('⚡', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: PfSpacing.xs),
                  Expanded(
                    child: Text(
                      agent.currentTask,
                      style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground, fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTokenProgress() {
    final totalTokens = agent.tokensIn + agent.tokensOut;
    final progress = (totalTokens / _maxTokens).clamp(0.0, 1.0);
    final inFraction = totalTokens > 0 ? agent.tokensIn / totalTokens : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Токены', style: PfTypography.caption.copyWith(color: PfColors.mutedForeground)),
            Text('$totalTokens / ${_maxTokens.toInt()}', style: PfTypography.caption.copyWith(color: PfColors.mutedForeground)),
          ],
        ),
        const SizedBox(height: PfSpacing.xs),
        ClipRRect(
          borderRadius: PfRadius.borderRadiusPill,
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: PfColors.muted),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (inFraction * 100).round().clamp(1, 99),
                        child: Container(color: PfColors.accentAdmin),
                      ),
                      Flexible(
                        flex: ((1 - inFraction) * 100).round().clamp(1, 99),
                        child: Container(color: PfColors.accentAdmin.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('IN: ${agent.tokensIn}', style: PfTypography.caption.copyWith(color: PfColors.accentAdmin, fontSize: 10)),
            Text('OUT: ${agent.tokensOut}', style: PfTypography.caption.copyWith(color: PfColors.accentAdmin.withValues(alpha: 0.7), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
