import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/features/admin/data/admin_repository.dart';
import 'package:app/features/admin/models/brain_model.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

// ─── Status helpers ──────────────────────────────────────────────────────────

const _statusColors = {
  'идея': Color(0xFF58A6FF),
  'idea': Color(0xFF58A6FF),
  'в-работе': Color(0xFF3FB950),
  'в работе': Color(0xFF3FB950),
  'in-progress': Color(0xFF3FB950),
  'готово': Color(0xFFD2A8FF),
  'done': Color(0xFFD2A8FF),
  'реализовано': Color(0xFFF0C040),
  'implemented': Color(0xFFF0C040),
};

Color statusColor(String? status) {
  if (status == null || status.isEmpty) return const Color(0xFF8B949E);
  return _statusColors[status.toLowerCase()] ?? const Color(0xFF8B949E);
}

bool isImplemented(String? status) {
  return status != null &&
      (status.toLowerCase() == 'реализовано' ||
          status.toLowerCase() == 'implemented');
}

String statusLabel(String? status) {
  if (status == null || status.isEmpty) return 'Без статуса';
  switch (status.toLowerCase()) {
    case 'идея':
    case 'idea':
      return '💡 Идея';
    case 'в-работе':
    case 'в работе':
    case 'in-progress':
      return '🔧 В работе';
    case 'готово':
    case 'done':
      return '✅ Готово';
    case 'реализовано':
    case 'implemented':
      return '🎯 Реализовано';
    default:
      return status;
  }
}

String folderIcon(String folder) {
  switch (folder) {
    case 'ideas':
      return '💡';
    case 'projects':
      return '📦';
    case 'daily':
      return '📅';
    case 'people':
      return '👤';
    case 'references':
      return '📚';
    case 'inbox':
      return '📥';
    default:
      return '📄';
  }
}

// ─── Brain Page ──────────────────────────────────────────────────────────────

class BrainPage extends StatefulWidget {
  const BrainPage({super.key});

  @override
  State<BrainPage> createState() => _BrainPageState();
}

class _BrainPageState extends State<BrainPage>
    with SingleTickerProviderStateMixin {
  late final AdminRepository _repo;
  late final TabController _tabCtrl;

  BrainGraph? _graph;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _repo = AdminRepository(DioClient(SecureStorage()).dio);
    _loadGraph();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGraph() async {
    setState(() => _isLoading = true);
    try {
      final graph = await _repo.getBrainGraph();
      if (mounted) {
        setState(() {
          _graph = graph;
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

  Future<void> _changeStatus(BrainNode node, String newStatus) async {
    try {
      await _repo.setBrainStatus(node.id, newStatus);
      await _loadGraph();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  void _showStatusDialog(BrainNode node) {
    final statusOptions = ['идея', 'в работе', 'готово', 'реализовано'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.cardColor
            : AppTheme.lightCardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const PhosphorIcon(PhosphorIconsFill.pencilLine, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                node.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statusOptions.map((s) {
            final active = node.status.toLowerCase() == s.toLowerCase();
            final color = statusColor(s);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: active
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _changeStatus(node, s);
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          statusLabel(s),
                          style: TextStyle(
                            color: active ? color : null,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        if (active) ...[
                          const Spacer(),
                          const PhosphorIcon(
                            PhosphorIconsFill.check,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('🧠 Второй мозг'),
        backgroundColor:
            isDark ? AppTheme.bgColor.withValues(alpha: 0.85) : surface.withValues(alpha: 0.85),
        elevation: 0,
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsFill.caretLeft),
          onPressed: () => context.go('/'),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.accentColor,
          labelColor: AppTheme.accentColor,
          unselectedLabelColor:
              isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
          tabs: const [
            Tab(icon: PhosphorIcon(PhosphorIconsFill.shareNetwork, size: 20), text: 'Граф'),
            Tab(icon: PhosphorIcon(PhosphorIconsFill.listDashes, size: 20), text: 'Лента'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _graph == null
                  ? const Center(child: Text('Нет данных'))
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _BrainGraphView(
                          graph: _graph!,
                          onNodeTap: _showStatusDialog,
                        ),
                        _BrainTimelineView(
                          graph: _graph!,
                          onNodeTap: _showStatusDialog,
                        ),
                      ],
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
              'Не удалось загрузить граф',
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
              onPressed: _loadGraph,
              icon: const PhosphorIcon(PhosphorIconsFill.arrowsClockwise),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Force-Directed Graph View ───────────────────────────────────────────────

class _BrainGraphView extends StatefulWidget {
  final BrainGraph graph;
  final void Function(BrainNode node) onNodeTap;

  const _BrainGraphView({required this.graph, required this.onNodeTap});

  @override
  State<_BrainGraphView> createState() => _BrainGraphViewState();
}

class _BrainGraphViewState extends State<_BrainGraphView>
    with SingleTickerProviderStateMixin {
  late final Map<String, _NodeState> _nodeStates;
  late AnimationController _animCtrl;
  final Map<String, Offset> _dragOffsets = {};
  final TransformationController _transformCtrl = TransformationController();
  double _canvasW = 2000;
  double _canvasH = 1500;

  @override
  void initState() {
    super.initState();
    _nodeStates = {};
    final nodes = widget.graph.nodes;
    final n = nodes.length;
    // Spread nodes in a circle for better initial layout
    for (int i = 0; i < n; i++) {
      final angle = 2 * math.pi * i / (n > 0 ? n : 1);
      final radius = 300.0 + (i % 3) * 80.0; // varied radius
      final node = nodes[i];
      _nodeStates[node.id] = _NodeState(
        x: _canvasW / 2 + radius * math.cos(angle),
        y: _canvasH / 2 + radius * math.sin(angle),
        vx: 0,
        vy: 0,
      );
    }
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_simulate);
    // Run initial simulation iterations
    _runInitialLayout();
    // Start animation
    _animCtrl.repeat();
  }

  void _runInitialLayout() {
    for (int i = 0; i < 300; i++) {
      _applyForces(0.03);
    }
    // Auto-fit after layout
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_simulate);
    _animCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _fitToScreen() {
    if (!mounted) return;
    final ctx = context;
    final mediaQuery = MediaQuery.of(ctx);
    final screenW = mediaQuery.size.width;
    final screenH = mediaQuery.size.height;

    // Find bounding box of all nodes
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in _nodeStates.values) {
      if (s.x < minX) minX = s.x;
      if (s.y < minY) minY = s.y;
      if (s.x > maxX) maxX = s.x;
      if (s.y > maxY) maxY = s.y;
    }
    final graphW = maxX - minX + 100;
    final graphH = maxY - minY + 100;
    if (graphW <= 0 || graphH <= 0) return;

    final scaleX = screenW / graphW;
    final scaleY = screenH / graphH;
    final scale = math.min(scaleX, scaleY) * 0.85;

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final tx = screenW / 2 - centerX * scale;
    final ty = screenH / 2 - centerY * scale;

    _transformCtrl.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  void _applyForces(double dt) {
    final nodes = widget.graph.nodes;
    final edges = widget.graph.edges;
    final states = _nodeStates;

    const repulsion = 30000.0;
    const attraction = 0.003;
    const damping = 0.88;
    const minDist = 40.0;

    // Reset forces
    for (final s in states.values) {
      s.fx = 0;
      s.fy = 0;
    }

    // Repulsive forces (all pairs)
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final a = states[nodes[i].id]!;
        final b = states[nodes[j].id]!;
        double dx = a.x - b.x;
        double dy = a.y - b.y;
        double dist = math.sqrt(dx * dx + dy * dy);
        if (dist < minDist) dist = minDist;
        final force = repulsion / (dist * dist);
        final fx = force * dx / dist;
        final fy = force * dy / dist;
        a.fx += fx;
        a.fy += fy;
        b.fx -= fx;
        b.fy -= fy;
      }
    }

    // Attractive forces (edges)
    for (final e in edges) {
      final a = states[e.source];
      final b = states[e.target];
      if (a == null || b == null) continue;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final force = attraction * (dist - 150);
      final fx = force * dx / (dist + 0.01);
      final fy = force * dy / (dist + 0.01);
      a.fx += fx;
      a.fy += fy;
      b.fx -= fx;
      b.fy -= fy;
    }

    // Soft center gravity
    for (final s in states.values) {
      s.fx -= (s.x - _canvasW / 2) * 0.0003;
      s.fy -= (s.y - _canvasH / 2) * 0.0003;
    }

    // Apply forces
    for (final entry in states.entries) {
      final s = entry.value;
      s.vx = (s.vx + s.fx * dt) * damping;
      s.vy = (s.vy + s.fy * dt) * damping;
      final drag = _dragOffsets[entry.key];
      if (drag != null) {
        s.x += (drag.dx - s.x) * 0.1;
        s.y += (drag.dy - s.y) * 0.1;
      } else {
        s.x += s.vx;
        s.y += s.vy;
      }
    }
  }

  void _simulate() {
    _applyForces(0.02);
    setState(() {});
  }

  void _toggleSimulation() {
    if (_animCtrl.isAnimating) {
      _animCtrl.stop();
    } else {
      _animCtrl.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.graph.nodes;
    final edges = widget.graph.edges;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final nodeSize = isMobile ? 32.0 : 44.0;
    final labelWidth = isMobile ? 80.0 : 100.0;
    final fontSize = isMobile ? 8.0 : 10.0;

    return Stack(
      children: [
        // Interactive viewer for zoom/pan
        InteractiveViewer(
          transformationController: _transformCtrl,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          minScale: 0.1,
          maxScale: 5.0,
          constrained: false,
          child: SizedBox(
            width: _canvasW,
            height: _canvasH,
            child: Stack(
              children: [
                // Edges layer
                CustomPaint(
                  size: Size(_canvasW, _canvasH),
                  painter: _EdgePainter(
                    edges: edges,
                    nodeStates: _nodeStates,
                    isDark: isDark,
                  ),
                ),
                // Nodes layer
                ...nodes.map((node) {
                  final state = _nodeStates[node.id];
                  if (state == null) return const SizedBox.shrink();
                  final color = statusColor(node.status);
                  final implemented = isImplemented(node.status);

                  return Positioned(
                    left: state.x - nodeSize / 2,
                    top: state.y - nodeSize / 2,
                    child: GestureDetector(
                      onTap: () => widget.onNodeTap(node),
                      onPanUpdate: (details) {
                        setState(() {
                          _dragOffsets[node.id] = Offset(
                            state.x + details.delta.dx,
                            state.y + details.delta.dy,
                          );
                        });
                      },
                      onPanEnd: (_) {
                        _dragOffsets.remove(node.id);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Node circle
                          Container(
                            width: nodeSize,
                            height: nodeSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.2),
                              border: Border.all(
                                color: color,
                                width: implemented ? 2.5 : 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.3),
                                  blurRadius: implemented ? 8 : 4,
                                  spreadRadius: implemented ? 2 : 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: implemented
                                  ? Text('✓',
                                      style: TextStyle(
                                          color: const Color(0xFFF0C040),
                                          fontSize: nodeSize * 0.4,
                                          fontWeight: FontWeight.bold))
                                  : Container(
                                      width: nodeSize * 0.25,
                                      height: nodeSize * 0.25,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: color,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          // Node label (always show)
                          SizedBox(
                            width: labelWidth,
                            child: Text(
                              node.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.textPrimary
                                    : AppTheme.lightTextPrimary,
                                fontSize: fontSize,
                                fontWeight: FontWeight.w500,
                                decoration: implemented
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: const Color(0xFFF0C040),
                              ),
                              maxLines: isMobile ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Controls overlay (not affected by zoom)
        Positioned(
          bottom: 12,
          left: 12,
          child: _GraphLegend(isDark: isDark, isCompact: isMobile),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'brain_fit',
                onPressed: _fitToScreen,
                backgroundColor: isDark
                    ? AppTheme.surfaceColor
                    : AppTheme.lightSurfaceColor,
                child: Icon(
                  PhosphorIconsFill.arrowsOut,
                  size: 16,
                  color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'brain_play',
                onPressed: _toggleSimulation,
                backgroundColor: isDark
                    ? AppTheme.surfaceColor
                    : AppTheme.lightSurfaceColor,
                child: Icon(
                  _animCtrl.isAnimating
                      ? PhosphorIconsFill.pause
                      : PhosphorIconsFill.play,
                  size: 16,
                  color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${nodes.length}·${edges.length}',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.textSecondary
                      : AppTheme.lightTextSecondary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NodeState {
  double x, y, vx, vy, fx, fy;
  _NodeState({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.fx = 0,
    this.fy = 0,
  });
}

class _EdgePainter extends CustomPainter {
  final List<BrainEdge> edges;
  final Map<String, _NodeState> nodeStates;
  final bool isDark;

  _EdgePainter({
    required this.edges,
    required this.nodeStates,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final e in edges) {
      final a = nodeStates[e.source];
      final b = nodeStates[e.target];
      if (a == null || b == null) continue;
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => true;
}

class _GraphLegend extends StatelessWidget {
  final bool isDark;
  final bool isCompact;
  const _GraphLegend({required this.isDark, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('💡', 'Идея', const Color(0xFF58A6FF)),
      ('🔧', 'В работе', const Color(0xFF3FB950)),
      ('✅', 'Готово', const Color(0xFFD2A8FF)),
      ('🎯', 'Реализовано', const Color(0xFFF0C040)),
    ];
    return Container(
      padding: EdgeInsets.all(isCompact ? 6 : 10),
      decoration: BoxDecoration(
        color: (isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor)
            .withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: entries.map((e) => Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 1 : 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.$1, style: TextStyle(fontSize: isCompact ? 9 : 11)),
              const SizedBox(width: 4),
              Container(
                width: isCompact ? 6 : 8,
                height: isCompact ? 6 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: e.$3,
                ),
              ),
              const SizedBox(width: 3),
              Text(e.$2,
                  style: TextStyle(
                    fontSize: isCompact ? 8 : 10,
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.lightTextSecondary,
                  )),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

// ─── Timeline View ───────────────────────────────────────────────────────────

class _BrainTimelineView extends StatefulWidget {
  final BrainGraph graph;
  final void Function(BrainNode node) onNodeTap;

  const _BrainTimelineView({required this.graph, required this.onNodeTap});

  @override
  State<_BrainTimelineView> createState() => _BrainTimelineViewState();
}

class _BrainTimelineViewState extends State<_BrainTimelineView> {
  String _search = '';

  List<BrainNode> get _filteredNodes {
    final nodes = widget.graph.nodes;
    if (_search.isEmpty) return nodes;
    final q = _search.toLowerCase();
    return nodes.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q)) ||
          n.folder.toLowerCase().contains(q) ||
          n.id.toLowerCase().contains(q);
    }).toList();
  }

  List<BrainNode> get _sortedNodes {
    final nodes = _filteredNodes;
    // Sort by date (most recent first), then undated at bottom
    final dated = nodes.where((n) => n.date.isNotEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final undated = nodes.where((n) => n.date.isEmpty).toList();
    return [...dated, ...undated];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nodes = _sortedNodes;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: TextStyle(
              color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Поиск по названию, тегам, папке…',
              hintStyle: TextStyle(
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.lightTextSecondary,
              ),
              prefixIcon: PhosphorIcon(
                PhosphorIconsFill.magnifyingGlass,
                size: 18,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.lightTextSecondary,
              ),
              filled: true,
              fillColor: isDark
                  ? AppTheme.surfaceColor
                  : AppTheme.lightSurfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text(
                '${nodes.length} записей',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.textSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: nodes.length,
            itemBuilder: (context, index) {
              final node = nodes[index];
              return _TimelineItem(
                node: node,
                isDark: isDark,
                onTap: () => widget.onNodeTap(node),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final BrainNode node;
  final bool isDark;
  final VoidCallback onTap;

  const _TimelineItem({
    required this.node,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = statusColor(node.status);
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;
    final textColor =
        isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Folder icon
                Text(folderIcon(node.folder), style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (node.date.isNotEmpty) ...[
                            Text(
                              node.date,
                              style: TextStyle(
                                color: subColor,
                                fontSize: 11,
                              ),
                            ),
                            const Text(' · ', style: TextStyle(fontSize: 11, color: Color(0xFF30363D))),
                          ],
                          Text(
                            node.folder,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status badge
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel(node.status),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
