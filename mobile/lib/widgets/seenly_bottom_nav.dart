import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_translations.dart';
import '../services/log_theme_service.dart';
import '../theme/log_theme_copy.dart';
import '../theme/clay_kit.dart';
import '../theme/palette.dart';
import '../theme/seenly_skin.dart';

class SeenlyBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SeenlyBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  // Home, collections, and profile stay put; the diary tab (index 1)
  // wears whichever LogTheme is active — see build().
  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'home'),
    (icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'diary'),
    (icon: Icons.bookmarks_outlined, activeIcon: Icons.bookmarks, label: 'collections'),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: 'profile'),
  ];

  static const _barHeight = 46.0;
  static const _pillSize = 42.0;
  static const _pillDuration = Duration(milliseconds: 420);
  static const _pillCurve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final logTheme = context.watch<LogThemeService>().theme;
    if (SeenlySkin.isClay) return _buildClay(logTheme);
    final cozy = SeenlySkin.isCozy;
    return Container(
      decoration: BoxDecoration(
        color: cozy ? SeenlyPalette.paper.withOpacity(0.96) : SeenlyPalette.background,
        border: Border(
          top: BorderSide(
            color: SeenlyPalette.border.withOpacity(cozy ? 0.75 : 1),
            width: cozy ? 0.8 : 0.5,
          ),
        ),
        borderRadius: cozy
            ? const BorderRadius.vertical(top: Radius.circular(24))
            : BorderRadius.zero,
        boxShadow: cozy
            ? [
                BoxShadow(
                  color: SeenlyPalette.shadowColor.withOpacity(SeenlyPalette.shadowOpacity),
                  blurRadius: 18,
                  offset: const Offset(0, -5),
                ),
              ]
            : const [],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / _items.length;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Soft accent pill that glides beneath the active tab.
                  AnimatedPositioned(
                    duration: _pillDuration,
                    curve: _pillCurve,
                    left: itemWidth * currentIndex + (itemWidth - _pillSize) / 2,
                    top: (_barHeight - _pillSize) / 2,
                    width: _pillSize,
                    height: _pillSize,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.85, end: 1),
                      duration: _pillDuration,
                      curve: Curves.easeOutBack,
                      key: ValueKey(currentIndex),
                      builder: (context, scale, child) => Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cozy ? SeenlyPalette.accent.withOpacity(0.14) : null,
                          gradient: cozy
                              ? null
                              : RadialGradient(
                                  colors: [
                                    SeenlyPalette.accent.withOpacity(0.20),
                                    SeenlyPalette.accent.withOpacity(0.06),
                                    SeenlyPalette.accent.withOpacity(0.0),
                                  ],
                                  stops: const [0.0, 0.65, 1.0],
                                ),
                          border: cozy
                              ? Border.all(
                                  color: SeenlyPalette.accent.withOpacity(0.12),
                                  width: 0.7,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (int i = 0; i < _items.length; i++)
                        SizedBox(
                          width: itemWidth,
                          height: _barHeight,
                          child: _NavItem(
                            icon: i == 1
                                ? LogThemeCopy.navIcon(logTheme, active: i == currentIndex)
                                : (i == currentIndex ? _items[i].activeIcon : _items[i].icon),
                            label: _items[i].label.tr,
                            active: i == currentIndex,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // Clay: a floating, puffy dock instead of a flat bar. The active tab is a
  // raised bubblegum bubble that glides between tabs and squishes on arrival;
  // inactive icons are soft and quiet. The strip behind the dock is the flat
  // page colour (ClayBackdrop's gradient ends on exactly that colour).
  Widget _buildClay(LogTheme logTheme) {
    const dockHeight = 66.0;
    const bubble = 50.0;
    return Container(
      color: SeenlyPalette.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
          child: ClaySurface(
            radius: 34,
            elevation: 0.95,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: dockHeight - 16,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / _items.length;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedPositioned(
                        duration: _pillDuration,
                        curve: Curves.easeOutBack,
                        left: itemWidth * currentIndex + (itemWidth - bubble) / 2,
                        top: (dockHeight - 16 - bubble) / 2,
                        width: bubble,
                        height: bubble,
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(currentIndex),
                          tween: Tween(begin: 0.78, end: 1),
                          duration: _pillDuration,
                          curve: Curves.elasticOut,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: ClaySurface(
                            radius: 22,
                            color: SeenlyPalette.accent,
                            glow: SeenlyPalette.accent,
                            elevation: 0.5,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (int i = 0; i < _items.length; i++)
                            SizedBox(
                              width: itemWidth,
                              height: dockHeight - 16,
                              child: _ClayNavItem(
                                icon: i == 1
                                    ? LogThemeCopy.navIcon(logTheme, active: i == currentIndex)
                                    : (i == currentIndex ? _items[i].activeIcon : _items[i].icon),
                                label: _items[i].label.tr,
                                active: i == currentIndex,
                                onTap: () => onTap(i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClayNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ClayNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            scale: active ? 1.08 : 0.94,
            child: Icon(
              icon,
              size: 26,
              color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? SeenlyPalette.accent : SeenlyPalette.placeholder;
    return Semantics(
      label: label,
      selected: active,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: SeenlyPalette.accent.withOpacity(0.08),
          highlightColor: SeenlyPalette.accent.withOpacity(0.05),
          child: Center(
            // Gentle lift + pop when a tab becomes active.
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutBack,
              offset: active ? const Offset(0, -0.08) : Offset.zero,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutBack,
                scale: active ? 1.12 : 1.0,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  builder: (context, animatedColor, child) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      icon,
                      key: ValueKey(icon),
                      size: 24,
                      color: animatedColor,
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
}
