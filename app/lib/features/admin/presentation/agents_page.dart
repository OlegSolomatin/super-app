import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/features/admin/data/admin_repository.dart';
import 'package:app/features/admin/models/agent_status.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

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
    setState(() {
      _isLoading = true;
      _error = null;
    });
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
        if (working.isNotEmpty) {
          sessionTask = working.first.currentTask;
        }
      }

      if (mounted) {
        setState(() {
          _agents = agents;
          _sessionTask = sessionTask;
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Мониторинг агентов',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ConstrainedContent(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Ошибка загрузки',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAgentStatuses,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final agents = _agents ?? [];

    return RefreshIndicator(
      onRefresh: _loadAgentStatuses,
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_sessionTask != null && _sessionTask!.isNotEmpty) ...[
            _buildSessionSection(),
            const SizedBox(height: 16),
          ],
          ...agents.map((agent) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AgentCard(
                  agent: agent,
                  pulseAnimation: _pulseAnimation,
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSessionSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
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
              const SizedBox(width: 10),
              Text(
                'Сессия',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '⚡ $_sessionTask',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final AgentStatus agent;
  final Animation<double> pulseAnimation;

  const _AgentCard({
    required this.agent,
    required this.pulseAnimation,
  });

  Color get _statusColor {
    if (agent.isError) return Colors.redAccent;
    if (agent.isWorking) return const Color(0xFFFFD700);
    return const Color(0xFF4CAF50);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status indicator
                agent.isWorking
                    ? AnimatedBuilder(
                        animation: pulseAnimation,
                        builder: (context, child) => Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _statusColor
                                .withValues(alpha: pulseAnimation.value),
                            boxShadow: [
                              BoxShadow(
                                color: _statusColor
                                    .withValues(alpha: pulseAnimation.value * 0.5),
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
                          boxShadow: [
                            BoxShadow(
                              color: _statusColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                const SizedBox(width: 12),
                // Name and role
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        agent.role,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Model and provider
            Row(
              children: [
                Icon(Icons.memory, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  '${agent.model} · ${agent.provider}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Token progress
            _buildTokenProgress(context),
            const SizedBox(height: 8),
            // Cost row
            if (agent.costUsd > 0)
              Row(
                children: [
                  Icon(Icons.attach_money, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Text(
                    '\$${agent.costUsd.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: Color(0xFF81C784),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            // Working task
            if (agent.isWorking && agent.currentTask.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      '⚡',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Выполняет: ${agent.currentTask}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
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
      ),
    );
  }

  Widget _buildTokenProgress(BuildContext context) {
    final totalTokens = agent.tokensIn + agent.tokensOut;
    final progress = (totalTokens / _maxTokens).clamp(0.0, 1.0);
    final inFraction =
        totalTokens > 0 ? agent.tokensIn / totalTokens : 0.5;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Токены',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            Text(
              '$totalTokens / ${_maxTokens.toInt()}',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (inFraction * 100).round().clamp(1, 99),
                        child: Container(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Flexible(
                        flex: ((1 - inFraction) * 100).round().clamp(1, 99),
                        child: Container(
                          color: theme.colorScheme.primary.withValues(alpha: 0.7),
                        ),
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
            Text(
              'IN: ${agent.tokensIn}',
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 10),
            ),
            Text(
              'OUT: ${agent.tokensOut}',
              style: TextStyle(
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
