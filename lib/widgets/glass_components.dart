import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';

/// Deep-navy gradient background with ambient glow orbs.
/// Wrap every top-level Scaffold body in this once; nested screens
/// inside a shell should set backgroundColor: Colors.transparent instead.
class GlassBackground extends StatelessWidget {
  final Widget child;
  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [glassNavy0, glassNavy1, glassNavy2]
              : const [glassLightBg0, glassLightBg1, glassLightBg2],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _GlowOrb(
                color: isDark
                    ? const Color(0x1F14B8A6)
                    : const Color(0x1814B8A6),
                size: 380),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: _GlowOrb(
                color: isDark
                    ? const Color(0x1710B981)
                    : const Color(0x1210B981),
                size: 320),
          ),
          Positioned(
            top: 200,
            right: -100,
            child: _GlowOrb(
                color: isDark
                    ? const Color(0x1214B8A6)
                    : const Color(0x0D14B8A6),
                size: 260),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

/// Core frosted-glass container — replaces plain Card everywhere.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double radius;
  final double blurSigma;
  final Color? surfaceColor;
  final bool showTopGloss;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 20,
    this.blurSigma = 24,
    this.surfaceColor,
    this.showTopGloss = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final surface = surfaceColor ??
        (isDark ? const Color(0x12FFFFFF) : const Color(0xB3FFFFFF));
    final borderColor =
        isDark ? const Color(0x21FFFFFF) : const Color(0x14000000);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.05);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              const BoxShadow(
                color: Color(0x0A14B8A6),
                blurRadius: 40,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTopGloss && isDark)
                Container(
                  height: 1,
                  margin: EdgeInsets.symmetric(horizontal: radius * 0.4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0x33FFFFFF),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              padding != null
                  ? Padding(padding: padding!, child: child)
                  : child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass AppBar — blurs content scrolling beneath it. In light mode it is solid
/// white: the bar sits outside the page background, and a translucent white over
/// the dark window base would render grey.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double blurSigma;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.blurSigma = 20,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor =
        isDark ? const Color(0x0DFFFFFF) : const Color(0xFFFFFFFF);
    final borderColor =
        isDark ? const Color(0x17FFFFFF) : const Color(0x0F000000);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(color: borderColor, width: 1),
            ),
          ),
          child: AppBar(
            title: title,
            actions: actions,
            leading: leading,
            automaticallyImplyLeading: automaticallyImplyLeading,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            systemOverlayStyle: brandStatusBarStyle(isDark),
            bottom: bottom,
          ),
        ),
      ),
    );
  }
}

/// Status bar that blends into the page: transparent, icons matching the
/// theme, and no Android grey contrast scrim behind it.
SystemUiOverlayStyle brandStatusBarStyle(bool dark) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

/// Floating pill-shaped glass bottom navigation bar.
class GlassNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  const GlassNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor =
        isDark ? const Color(0x14FFFFFF) : const Color(0xBFFFFFFF);
    final borderColor =
        isDark ? const Color(0x24FFFFFF) : const Color(0x14000000);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
              backgroundColor: Colors.transparent,
              elevation: 0,
              height: 64,
              indicatorColor: const Color(0x3314B8A6),
              labelBehavior:
                  NavigationDestinationLabelBehavior.alwaysShow,
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient primary button with blue glow.
class GlassPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double? width;

  const GlassPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? const [Color(0xFF12A394), Color(0xFF0F766E)]
                : context.isDark
                    ? [const Color(0x1AFFFFFF), const Color(0x1AFFFFFF)]
                    : [const Color(0x1A000000), const Color(0x1A000000)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  const BoxShadow(
                    color: Color(0x5914B8A6),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Coloured status chip with glass tint.
class GlassChip extends StatelessWidget {
  final String label;
  final Color color;

  const GlassChip(
      {super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: color.withOpacity(0.30), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
