import 'package:flutter/material.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_typography.dart';

/// Аватар pfumiko design system.
///
/// Всегда с AvatarFallback (инициалы) на случай ошибки загрузки изображения.
///
/// Sizes:
/// - `sm` — 24px
/// - `md` — 32px (по умолчанию)
/// - `lg` — 40px
class PfAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final String size;

  const PfAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.size = 'md',
  });

  double get _size {
    switch (size) {
      case 'sm':
        return 24;
      case 'md':
        return 32;
      case 'lg':
        return 40;
      default:
        return 32;
    }
  }

  double get _fontSize {
    switch (size) {
      case 'sm':
        return 10;
      case 'md':
        return 12;
      case 'lg':
        return 14;
      default:
        return 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    final diameter = _size;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: diameter / 2,
        backgroundImage: NetworkImage(imageUrl!),
        backgroundColor: PfColors.surface,
        child: _fallback(),
      );
    }

    return CircleAvatar(
      radius: diameter / 2,
      backgroundColor: PfColors.surface,
      child: _fallback(),
    );
  }

  Widget _fallback() {
    return Text(
      initials.isNotEmpty ? initials.substring(0, 1).toUpperCase() : '?',
      style: PfTypography.caption.copyWith(
        fontSize: _fontSize,
        fontWeight: FontWeight.w600,
        color: PfColors.mutedForeground,
      ),
    );
  }
}
