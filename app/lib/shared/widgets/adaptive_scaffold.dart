import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/core/section_theme.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/shared/widgets/pf_divider.dart';

/// Navigation destination for sidebar.
class NavDestination {
  final PhosphorIconData icon;
  final String label;
  final String path;
  final bool isActive;
  final SectionTheme section;

  const NavDestination({
    required this.icon,
    required this.label,
    required this.path,
    this.isActive = false,
    this.section = SectionTheme.home,
  });
}

/// Adaptive scaffold: drawer on mobile, sidebar + top bar on desktop.
///
/// Sidebar: Linear deep dark (#010102), active indicator слева.
/// Top bar: 64px, чистый, с заголовком и actions.
class AdaptiveScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final List<NavDestination>? navDestinations;
  final String? currentPath;
  final Widget? profileHeader;
  final String? username;
  final String? userInitials;
  final VoidCallback? onLogout;
  final bool showBackButton;

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
    this.username,
    this.userInitials,
    this.onLogout,
    this.showBackButton = false,
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

  // ─── Mobile Layout ──────────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    final section = context.watch<ThemeProvider>().section;

    return Scaffold(
      backgroundColor: PfColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
        ),
        backgroundColor: PfColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: showBackButton
            ? IconButton(
                icon: const PhosphorIcon(
                  PhosphorIconsFill.caretLeft,
                  color: PfColors.foreground,
                  size: 22,
                ),
                onPressed: () => context.pop(),
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: PhosphorIcon(
                    PhosphorIconsFill.list,
                    color: PfColors.foreground,
                    size: 22,
                  ),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: actions,
      ),
      drawer: _buildSidebar(context, section, isCompact: false, isDrawer: true),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }

  // ─── Desktop Layout ────────────────────────────────────────────────
  Widget _buildDesktopLayout(BuildContext context, ScreenSize screenSize) {
    final section = context.watch<ThemeProvider>().section;
    final isTablet = screenSize == ScreenSize.tablet;

    return Scaffold(
      backgroundColor: PfColors.background,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────
          _buildSidebar(context, section, isCompact: isTablet, isDrawer: false),

          // ── Main content ──────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, section),
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

  // ─── Sidebar ────────────────────────────────────────────────────────
  Widget _buildSidebar(
    BuildContext context,
    SectionTheme section, {
    required bool isCompact,
    required bool isDrawer,
  }) {
    final nav = navDestinations ?? [];
    final sidebarWidth = isCompact ? 64.0 : 240.0;

    Widget sidebar = Container(
      width: isCompact ? 64 : 240,
      color: PfColors.sidebar,
      child: Column(
        children: [
          // Logo / Wordmark
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 0 : PfSpacing.lg,
            ),
            alignment: Alignment.center,
            child: isCompact
                ? PhosphorIcon(
                    PhosphorIconsFill.rocketLaunch,
                    color: section.accent,
                    size: 24,
                  )
                : Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIconsFill.rocketLaunch,
                        color: section.accent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Super App',
                        style: TextStyle(
                          color: PfColors.sidebarForeground,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
          ),

          const PfDivider(color: PfColors.sidebarHairline),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 4 : PfSpacing.sm,
                vertical: PfSpacing.xs,
              ),
              itemCount: nav.length,
              itemBuilder: (context, index) {
                final dest = nav[index];
                final active = dest.path == currentPath;
                return _SidebarItem(
                  icon: dest.icon,
                  label: dest.label,
                  section: dest.section,
                  isActive: active,
                  isCompact: isCompact,
                  onTap: () {
                    if (dest.path != currentPath) {
                      context.read<ThemeProvider>().setSection(dest.section);
                      if (isDrawer) Navigator.of(context).pop();
                      context.go(dest.path);
                    }
                  },
                );
              },
            ),
          ),

          // Bottom section: Settings + Theme + User
          const PfDivider(color: PfColors.sidebarHairline),

          if (!isCompact) _buildUserSection(context, section),
          if (isCompact) _buildCompactUserSection(context),
        ],
      ),
    );

    if (isDrawer) {
      return Drawer(
        width: sidebarWidth,
        child: sidebar,
      );
    }
    return sidebar;
  }

  // ─── User Section (full sidebar) ───────────────────────────────────
  Widget _buildUserSection(BuildContext context, SectionTheme section) {
    return Padding(
      padding: const EdgeInsets.all(PfSpacing.sm),
      child: Column(
        children: [
          // Settings
          _SidebarItem(
            icon: PhosphorIconsFill.gearSix,
            label: 'Настройки',
            section: SectionTheme.settings,
            isActive: false,
            isCompact: false,
            onTap: () {
              context.read<ThemeProvider>().setSection(SectionTheme.settings);
              context.go('/settings');
            },
          ),
          const SizedBox(height: 4),
          // User row: avatar + name + logout
          Container(
            padding: const EdgeInsets.all(PfSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: PfRadius.borderRadiusLg,
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 16,
                  backgroundColor: section.accent.withValues(alpha: 0.2),
                  child: Text(
                    userInitials ?? '?',
                    style: PfTypography.caption.copyWith(
                      color: section.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    username ?? 'Пользователь',
                    style: PfTypography.bodySm.copyWith(
                      color: PfColors.sidebarForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Theme toggle
                GestureDetector(
                  onTap: () => _showThemeSheet(context),
                  child: PhosphorIcon(
                    PhosphorIconsFill.sun,
                    color: PfColors.mutedForeground,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                // Logout
                GestureDetector(
                  onTap: onLogout,
                  child: PhosphorIcon(
                    PhosphorIconsFill.signOut,
                    color: PfColors.destructive,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── User Section (compact sidebar) ────────────────────────────────
  Widget _buildCompactUserSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PfSpacing.sm),
      child: Column(
        children: [
          _SidebarItem(
            icon: PhosphorIconsFill.gearSix,
            label: '',
            section: SectionTheme.settings,
            isActive: false,
            isCompact: true,
            onTap: () {
              context.read<ThemeProvider>().setSection(SectionTheme.settings);
              context.go('/settings');
            },
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onLogout,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: PfRadius.borderRadiusLg,
              ),
              child: PhosphorIcon(
                PhosphorIconsFill.signOut,
                color: PfColors.destructive,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, SectionTheme section) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
      decoration: BoxDecoration(
        color: PfColors.background,
        border: const Border(
          bottom: BorderSide(color: PfColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (showBackButton) ...[
            IconButton(
              icon: const PhosphorIcon(
                PhosphorIconsFill.caretLeft,
                color: PfColors.foreground,
                size: 20,
              ),
              onPressed: () => context.pop(),
              visualDensity: VisualDensity.compact,
              tooltip: 'Назад',
            ),
            const SizedBox(width: PfSpacing.xs),
          ],
          // Section icon + title
          PhosphorIcon(
            section.icon,
            color: section.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }

  // ─── Theme Sheet ────────────────────────────────────────────────────
  void _showThemeSheet(BuildContext context) {
    final provider = context.read<ThemeProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: PfColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PfSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: PfColors.mutedForeground,
                  borderRadius: PfRadius.borderRadiusPill,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Тема оформления',
                style: PfTypography.titleLg.copyWith(color: PfColors.foreground),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ThemeOption(
                    icon: PhosphorIconsFill.moon,
                    section: SectionTheme.home,
                    label: 'Тёмная',
                    active: provider.mode == ThemeModePreference.dark,
                    onTap: () {
                      provider.setMode(ThemeModePreference.dark);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    icon: PhosphorIconsFill.desktop,
                    section: SectionTheme.home,
                    label: 'Системная',
                    active: provider.mode == ThemeModePreference.system,
                    onTap: () {
                      provider.setMode(ThemeModePreference.system);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    icon: PhosphorIconsFill.sun,
                    section: SectionTheme.home,
                    label: 'Светлая',
                    active: provider.mode == ThemeModePreference.light,
                    onTap: () {
                      provider.setMode(ThemeModePreference.light);
                      Navigator.pop(ctx);
                    },
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

// ─── Sidebar Item ───────────────────────────────────────────────────────
class _SidebarItem extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final SectionTheme section;
  final bool isActive;
  final bool isCompact;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.section,
    required this.isActive,
    required this.isCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: PfRadius.borderRadiusLg,
          onTap: onTap,
          child: Container(
            padding: isCompact
                ? const EdgeInsets.symmetric(vertical: 12)
                : const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: PfSpacing.sm,
                  ),
            decoration: BoxDecoration(
              color: isActive
                  ? section.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: PfRadius.borderRadiusLg,
              border: isActive
                  ? const Border(
                      left: BorderSide(
                        color: Color(0xFF5E6AD2),
                        width: 3,
                      ),
                    )
                  : null,
            ),
            child: isCompact
                ? Center(
                    child: PhosphorIcon(
                      icon,
                      color: isActive ? section.accent : PfColors.mutedForeground,
                      size: 22,
                    ),
                  )
                : Row(
                    children: [
                      const SizedBox(width: 4),
                      PhosphorIcon(
                        icon,
                        color: isActive ? section.accent : PfColors.mutedForeground,
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        label,
                        style: TextStyle(
                          color: isActive ? PfColors.sidebarForeground : PfColors.mutedForeground,
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
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

// ─── Theme Option ───────────────────────────────────────────────────────
class _ThemeOption extends StatelessWidget {
  final PhosphorIconData icon;
  final SectionTheme section;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.section,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: active
              ? section.accent.withValues(alpha: 0.15)
              : PfColors.surface,
          borderRadius: PfRadius.borderRadiusXl,
          border: Border.all(
            color: active ? section.accent : PfColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              icon,
              color: active ? section.accent : PfColors.foreground,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active ? section.accent : PfColors.mutedForeground,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
