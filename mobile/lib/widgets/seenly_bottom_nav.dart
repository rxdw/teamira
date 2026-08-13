import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/log_theme_service.dart';
import '../theme/log_theme_copy.dart';
import '../theme/palette.dart';

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
    return Container(
      decoration: const BoxDecoration(
        color: SeenlyPalette.background,
        border: Border(top: BorderSide(color: SeenlyPalette.border, width: 0.5)),
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
                          gradient: RadialGradient(
                            colors: [
                              SeenlyPalette.accent.withOpacity(0.20),
                              SeenlyPalette.accent.withOpacity(0.06),
                              SeenlyPalette.accent.withOpacity(0.0),
                            ],
                            stops: const [0.0, 0.65, 1.0],
                          ),
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
                            label: _items[i].label,
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
