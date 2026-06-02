import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';

/// Кнопка pfumiko design system.
///
/// Variants:
/// - `primary` — accent-filled, pill shape (CTA)
/// - `secondary` — surface background, rounded
/// - `ghost` — transparent, hover-only
/// - `outline` — border + transparent bg
/// - `destructive` — red, destructive actions
/// - `link` — text-only, accent color
///
/// Sizes:
/// - `sm` — 32px (для компактных интерфейсов)
/// - `md` — 36px (стандартная)
/// - `lg` — 40px (основная CTA)
/// - `pill` — 44px (акцентная CTA на hero)
/// - `icon-sm` — 32x32
/// - `icon-md` — 36x36
/// - `icon-lg` — 44x44
class PfButton extends StatelessWidget {
  final String variant;
  final String size;
  final String label;
  final PhosphorIconData? icon;
  final bool iconEnd;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool expanded;

  const PfButton({
    super.key,
    this.variant = 'primary',
    this.size = 'md',
    required this.label,
    this.icon,
    this.iconEnd = false,
    this.onPressed,
    this.isLoading = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    // ─── Colors by variant ────────────────────────────────────────────
    Color bgColor;
    Color fgColor;
    Color? borderColor;
    BorderRadius borderRadius;

    switch (variant) {
      case 'primary':
        bgColor = Theme.of(context).colorScheme.primary;
        fgColor = Theme.of(context).colorScheme.onPrimary;
        borderRadius = PfRadius.borderRadiusPill;
      case 'secondary':
        bgColor = PfColors.surface;
        fgColor = PfColors.foreground;
        borderRadius = PfRadius.borderRadiusLg;
      case 'ghost':
        bgColor = Colors.transparent;
        fgColor = PfColors.foreground;
        borderRadius = PfRadius.borderRadiusLg;
      case 'outline':
        bgColor = Colors.transparent;
        fgColor = PfColors.foreground;
        borderColor = PfColors.border;
        borderRadius = PfRadius.borderRadiusLg;
      case 'destructive':
        bgColor = PfColors.destructive;
        fgColor = Colors.white;
        borderRadius = PfRadius.borderRadiusMd;
      case 'link':
        bgColor = Colors.transparent;
        fgColor = Theme.of(context).colorScheme.primary;
        borderRadius = PfRadius.borderRadiusLg;
      default:
        bgColor = Theme.of(context).colorScheme.primary;
        fgColor = Theme.of(context).colorScheme.onPrimary;
        borderRadius = PfRadius.borderRadiusPill;
    }

    // ─── Size ──────────────────────────────────────────────────────────
    double height;
    EdgeInsets padding;
    double iconSize;

    switch (size) {
      case 'sm':
        height = 32;
        padding = const EdgeInsets.symmetric(horizontal: PfSpacing.sm);
        iconSize = 14;
      case 'md':
        height = 36;
        padding = const EdgeInsets.symmetric(horizontal: PfSpacing.md);
        iconSize = 16;
      case 'lg':
        height = 40;
        padding = const EdgeInsets.symmetric(horizontal: PfSpacing.lg);
        iconSize = 16;
      case 'pill':
        height = 44;
        padding = const EdgeInsets.symmetric(horizontal: 32);
        iconSize = 18;
      case 'icon-sm':
        height = 32;
        padding = EdgeInsets.zero;
        iconSize = 16;
      case 'icon-md':
        height = 36;
        padding = EdgeInsets.zero;
        iconSize = 18;
      case 'icon-lg':
        height = 44;
        padding = EdgeInsets.zero;
        iconSize = 22;
      default:
        height = 36;
        padding = const EdgeInsets.symmetric(horizontal: PfSpacing.md);
        iconSize = 16;
    }

    // ─── Content ───────────────────────────────────────────────────────
    Widget content;

    if (size.startsWith('icon')) {
      content = SizedBox(
        width: height,
        height: height,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fgColor,
                  ),
                )
              : PhosphorIcon(
                  icon ?? PhosphorIconsFill.circle,
                  size: iconSize,
                  color: fgColor,
                ),
        ),
      );
    } else {
      final children = <Widget>[];
      if (isLoading) {
        children.add(
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fgColor,
            ),
          ),
        );
        children.add(const SizedBox(width: PfSpacing.xs));
      } else if (icon != null && !iconEnd) {
        children.add(PhosphorIcon(icon!, size: iconSize, color: fgColor));
        children.add(const SizedBox(width: PfSpacing.xs));
      }

      children.add(
        Text(
          label,
          style: PfTypography.button.copyWith(color: fgColor),
        ),
      );

      if (icon != null && iconEnd) {
        children.add(const SizedBox(width: PfSpacing.xs));
        children.add(PhosphorIcon(icon!, size: iconSize, color: fgColor));
      }

      content = Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      );
    }

    // ─── Build ─────────────────────────────────────────────────────────
    final button = Container(
      height: size.startsWith('icon') ? null : height,
      constraints: size.startsWith('icon')
          ? BoxConstraints.tightFor(width: height, height: height)
          : expanded
              ? BoxConstraints.tightFor(height: height)
              : BoxConstraints.tightFor(height: height),
      decoration: BoxDecoration(
        color: isDisabled ? bgColor.withValues(alpha: 0.5) : bgColor,
        borderRadius: borderRadius,
        border: borderColor != null
            ? Border.all(color: isDisabled ? borderColor.withValues(alpha: 0.5) : borderColor)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: borderRadius,
          child: Padding(
            padding: padding,
            child: content,
          ),
        ),
      ),
    );

    return button;
  }
}
