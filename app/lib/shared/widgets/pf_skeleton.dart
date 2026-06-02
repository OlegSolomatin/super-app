import 'package:flutter/material.dart';
import 'package:app/shared/tokens/pf_radius.dart';

/// Скелетон (placeholder загрузки) pfumiko design system.
///
/// Использовать вместо raw `animate-pulse` / shimmer.
/// Анимация пульсации (fade in-out) встроена.
class PfSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final String shape;
  final double borderRadius;

  const PfSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.shape = 'rect',
    this.borderRadius = 6,
  });

  @override
  State<PfSkeleton> createState() => _PfSkeletonState();
}

class _PfSkeletonState extends State<PfSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCircle = widget.shape == 'circle';
    final borderRadius = isCircle
        ? PfRadius.borderRadiusPill
        : BorderRadius.circular(widget.borderRadius);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08 * _anim.value)
                : Colors.black.withValues(alpha: 0.06 * _anim.value),
            borderRadius: borderRadius,
          ),
        );
      },
    );
  }
}
