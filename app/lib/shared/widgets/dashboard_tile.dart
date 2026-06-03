import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_typography.dart';

/// Data for a dashboard tile.
class DashboardTileData {
  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const DashboardTileData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.isHighlighted = false,
  });
}

/// Dashboard tile — flat + hairline, без glassmorphism.
///
/// Flat фон `--card`, hairline border `--border`, иконка в цветном круге.
/// У highlight-плитки (admin) — чуть ярче border + тонкая подсветка.
class DashboardTile extends StatefulWidget {
  final DashboardTileData data;
  final int index;

  const DashboardTile({
    super.key,
    required this.data,
    this.index = 0,
  });

  @override
  State<DashboardTile> createState() => _DashboardTileState();
}

class _DashboardTileState extends State<DashboardTile>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: 80 * widget.index), () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final isAdmin = d.isHighlighted;
    final pc = PfColors.of(context);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            d.onTap?.call();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: pc.cardC,
                borderRadius: PfRadius.borderRadiusXxl,
                border: Border.all(
                  color: isAdmin
                      ? d.color.withValues(alpha: 0.4)
                      : pc.borderC,
                  width: isAdmin ? 1.5 : 1,
                ),
                boxShadow: isAdmin
                    ? [
                        BoxShadow(
                          color: d.color.withValues(alpha: 0.1),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: PfRadius.borderRadiusXxl,
                  onTap: d.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon circle — flat gradient, no glow
                        _buildIcon(d.color, isAdmin),
                        const SizedBox(height: 14),
                        // Title
                        Text(
                          d.title,
                          style: PfTypography.titleMd.copyWith(
                            color: pc.foregroundC,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        // Subtitle
                        Text(
                          d.subtitle,
                          style: PfTypography.caption.copyWith(
                            color: pc.mutedForegroundC,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Color color, bool isAdmin) {
    final iconSize = isAdmin ? 28.0 : 24.0;
    final containerSize = isAdmin ? 48.0 : 44.0;

    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: PhosphorIcon(
          widget.data.icon,
          size: iconSize,
          color: color,
        ),
      ),
    );
  }
}
