import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/theme.dart';

/// Data for a dashboard tile.
class DashboardTileData {
  final IconData icon;
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

/// Reusable dashboard tile with glassmorphism, animations, and guaranteed centering.
///
/// All layout (icon size, text spacing, centering) is handled internally.
/// Just pass data and it works — no manual alignment needed for new tiles.
class DashboardTile extends StatefulWidget {
  final DashboardTileData data;
  final int index; // for staggered animation

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
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
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
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );
    if (widget.data.isHighlighted) {
      _pulseCtrl.repeat(reverse: true);
    }

    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = widget.data.isHighlighted;
    final pulseVal = _pulseAnim.value;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            final tap = widget.data.onTap;
            if (tap != null) {
              tap();
            } else {
              _showComingSoon();
            }
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAdmin
                          ? AppTheme.accentColor
                              .withValues(alpha: 0.25 + 0.35 * pulseVal)
                          : isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.06),
                      width: isAdmin ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (isAdmin)
                        BoxShadow(
                          color: AppTheme.accentColor
                              .withValues(alpha: 0.12 + 0.18 * pulseVal),
                          blurRadius: 12 + 10 * pulseVal,
                          spreadRadius: 1 * pulseVal,
                        )
                      else
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      children: [
                        // Background layer
                        Positioned.fill(
                          child: isDark
                              ? _buildGlassBackground()
                              : _buildLightBackground(),
                        ),
                        // Content layer
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              final tap = widget.data.onTap;
                              if (tap != null) {
                                tap();
                              } else {
                                _showComingSoon();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 18,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Icon — guaranteed centered in its container
                                    _buildIcon(isAdmin, isDark),
                                    const SizedBox(height: 12),
                                    // Title — always left-aligned
                                    Text(
                                      widget.data.title,
                                      textAlign: TextAlign.start,
                                      style: TextStyle(
                                        color: isDark
                                            ? AppTheme.textPrimary
                                            : AppTheme.lightTextPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    // Subtitle — always left-aligned
                                    Text(
                                      widget.data.subtitle,
                                      style: TextStyle(
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : AppTheme.lightTextSecondary,
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.start,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.data.color.withValues(alpha: 0.12),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildLightBackground() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCardColor,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildIcon(bool isAdmin, bool isDark) {
    final iconSize = isAdmin ? 30.0 : 26.0;
    final containerSize = isAdmin ? 56.0 : 52.0;

    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            widget.data.color.withValues(alpha: 0.25),
            widget.data.color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: widget.data.color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              widget.data.color,
              widget.data.color.withValues(alpha: 0.6),
            ],
          ).createShader(bounds),
          child: Icon(
            widget.data.icon,
            size: iconSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.data.title} — скоро'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
