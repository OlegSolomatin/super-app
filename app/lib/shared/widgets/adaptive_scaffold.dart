import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:app/core/theme.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

/// Navigation destination for the sidebar.
class NavDestination {
  final Widget icon;
  final String label;
  final String path;
  final bool isActive;

  const NavDestination({
    required this.icon,
    required this.label,
    required this.path,
    this.isActive = false,
  });
}

/// Adaptive scaffold: drawer on mobile, sidebar + top bar on desktop.
class AdaptiveScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final List<NavDestination>? navDestinations;
  final String? currentPath;
  final Widget? profileHeader; // custom profile widget for desktop sidebar

  const AdaptiveScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.drawer,
    this.floatingActionButton,
    this.navDestinations,
    this.currentPath,
    this.profileHeader,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      builder: (context, screenSize, width) {
        if (screenSize == ScreenSize.mobile) {
          return _buildMobileLayout(context);
        }
        return _buildDesktopLayout(context, screenSize);
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.bgColor.withValues(alpha: 0.85)
            : AppTheme.lightSurfaceColor.withValues(alpha: 0.85),
        elevation: 0,
        actions: [
          if (drawer != null)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                tooltip: 'Меню',
              ),
            ),
          if (actions != null) ...actions!,
        ],
      ),
      endDrawer: drawer,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildDesktopLayout(BuildContext context, ScreenSize screenSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;
    final textColor =
        isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    final nav = navDestinations ?? [];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────
          Container(
            width: screenSize == ScreenSize.tablet ? 72 : 240,
            decoration: BoxDecoration(
              color: surface.withValues(alpha: 0.95),
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Column(
              children: [
                // Sidebar header
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenSize == ScreenSize.tablet ? 0 : 20,
                    vertical: 20,
                  ),
                  child: profileHeader ??
                    (screenSize == ScreenSize.tablet
                      ? const Icon(
                          Icons.rocket_launch,
                          color: AppTheme.accentColor,
                          size: 28,
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.rocket_launch,
                              color: AppTheme.accentColor,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              title,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )),
                ),
                const SizedBox(height: 8),
                // Navigation items
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenSize == ScreenSize.tablet ? 4 : 12,
                    ),
                    itemCount: nav.length + 2, // + обводка и настройки
                    itemBuilder: (context, index) {
                      if (index < nav.length) {
                        final dest = nav[index];
                        final active = dest.path == currentPath;
                        return _NavItem(
                          icon: dest.icon,
                          label: dest.label,
                          isActive: active,
                          isCompact: screenSize == ScreenSize.tablet,
                          onTap: () {
                            if (dest.path != currentPath) {
                              context.go(dest.path);
                            }
                          },
                        );
                      }
                      if (index == nav.length) {
                        // spacer
                        return const SizedBox.shrink();
                      }
                      // Settings / theme
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenSize == ScreenSize.tablet ? 0 : 8,
                          vertical: 4,
                        ),
                        child: _NavItem(
                          icon: const Icon(
                            PhosphorIconsFill.sun,
                            size: 20,
                          ),
                          label: 'Тема',
                          isActive: false,
                          isCompact: screenSize == ScreenSize.tablet,
                          onTap: () => _showThemeSheet(context),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Main content ──────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Top bar
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.5),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (actions != null) ...actions!,
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor;
    final provider = context.read<ThemeProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Тема оформления',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ThemeOption(
                    icon: '🌙',
                    label: 'Тёмная',
                    active: provider.mode == ThemeModePreference.dark,
                    onTap: () { provider.setMode(ThemeModePreference.dark); Navigator.pop(ctx); },
                  ),
                  _ThemeOption(
                    icon: '💻',
                    label: 'Системная',
                    active: provider.mode == ThemeModePreference.system,
                    onTap: () { provider.setMode(ThemeModePreference.system); Navigator.pop(ctx); },
                  ),
                  _ThemeOption(
                    icon: '☀️',
                    label: 'Светлая',
                    active: provider.mode == ThemeModePreference.light,
                    onTap: () { provider.setMode(ThemeModePreference.light); Navigator.pop(ctx); },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Nav Item ─────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool isActive;
  final bool isCompact;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTextColor =
        isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: isCompact
                ? const EdgeInsets.symmetric(vertical: 12, horizontal: 0)
                : const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.accentColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: isCompact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          color: isActive
                              ? AppTheme.accentColor
                              : defaultTextColor.withValues(alpha: 0.7),
                          size: 22,
                        ),
                        child: icon,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label.length > 3 ? label.substring(0, 3) : label,
                        style: TextStyle(
                          color: isActive
                              ? AppTheme.accentColor
                              : defaultTextColor.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: IconTheme(
                          data: IconThemeData(
                            color: isActive
                                ? AppTheme.accentColor
                                : defaultTextColor.withValues(alpha: 0.7),
                            size: 22,
                          ),
                          child: icon,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        label,
                        style: TextStyle(
                          color: isActive
                              ? AppTheme.accentColor
                              : defaultTextColor,
                          fontSize: 15,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (isActive)
                        const Spacer(),
                      if (isActive)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppTheme.accentColor,
                            shape: BoxShape.circle,
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

// ─── Theme Option (bottom sheet) ──────────────────────────────────────────────

class _ThemeOption extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface =
        isDark ? AppTheme.cardColor : AppTheme.lightCardColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: active ? AppTheme.accentColor.withValues(alpha: 0.15) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? AppTheme.accentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active ? AppTheme.accentColor : null,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
