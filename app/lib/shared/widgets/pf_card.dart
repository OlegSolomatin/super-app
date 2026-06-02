import 'package:flutter/material.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
/// Карточка pfumiko design system.
///
/// Flat + hairline, без теней — цветовой контраст создаёт глубину.
///
/// Variants:
/// - `default` — стандартная карточка с hairline 1px
/// - `elevated` — карточка без hairline, светлее на 1 уровень (для наложения)
/// - `trading` — плотная карточка для таблиц/списков
class PfCard extends StatelessWidget {
  final Widget? header;
  final Widget? footer;
  final Widget? child;
  final String variant;
  final EdgeInsets padding;
  final EdgeInsets? headerPadding;
  final EdgeInsets? footerPadding;
  final VoidCallback? onTap;

  const PfCard({
    super.key,
    this.header,
    this.footer,
    this.child,
    this.variant = 'default',
    EdgeInsets? padding,
    this.headerPadding,
    this.footerPadding,
    this.onTap,
  }) : padding = padding ?? const EdgeInsets.all(PfSpacing.lg);

  EdgeInsets get _headerPadding =>
      headerPadding ?? const EdgeInsets.only(bottom: PfSpacing.sm);
  EdgeInsets get _footerPadding =>
      footerPadding ?? const EdgeInsets.only(top: PfSpacing.sm);

  @override
  Widget build(BuildContext context) {
    final isTrading = variant == 'trading';
    final effectivePadding = isTrading
        ? const EdgeInsets.all(PfSpacing.md)
        : padding;

    final card = Container(
      decoration: BoxDecoration(
        color: PfColors.card,
        borderRadius: PfRadius.borderRadiusXl,
        border: Border.all(
          color: PfColors.border,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: PfRadius.borderRadiusXl,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: PfRadius.borderRadiusXl,
            child: Padding(
              padding: effectivePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (header != null)
                    Padding(
                      padding: _headerPadding,
                      child: header!,
                    ),
                  if (child != null) child!,
                  if (footer != null)
                    Padding(
                      padding: _footerPadding,
                      child: footer!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return card;
  }
}
