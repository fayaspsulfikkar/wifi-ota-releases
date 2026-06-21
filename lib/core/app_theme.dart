/// App-wide Liquid Glass design system.
///
/// Provides [AppColors], [AppTextStyles], and reusable glass widgets
/// ([GlassPanel], [GradientScaffold], [GlassButton], [GlassIconButton]).
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colors ───────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Background gradient
  static const bgGradientStart = Color(0xFF0A0A1A);
  static const bgGradientMid = Color(0xFF1A1035);
  static const bgGradientEnd = Color(0xFF0D1B2A);
  static const bgElevated = Color(0xFF161A1D);

  // Glass surfaces
  static Color glassFill = Colors.white.withOpacity(0.07);
  static Color glassBorder = Colors.white.withOpacity(0.14);
  static Color glassHighlight = Colors.white.withOpacity(0.22);
  static Color glassHighlightEnd = Colors.white.withOpacity(0.04);

  // Accent
  static const accent = Color(0xFF7C6BFF);
  static const accentGlow = Color(0xFF9D8FFF);
  static const accentSoft = Color(0xFFA29BFE);

  // Semantic
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);

  // Text
  static const textPrimary = Color(0xFFF8F8FF);
  static const textSecondary = Color(0xFF9CA3AF);

  // Misc
  static const border = Color(0xFF2A2A3A);
  static const divider = Color(0x1AFFFFFF); // white 10%
}

// ─── Text Styles ──────────────────────────────────────────────────────────

class AppTextStyles {
  AppTextStyles._();

  static TextStyle heading1 = GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle heading2 = GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static TextStyle heading3 = GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle body = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyMedium = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static TextStyle caption = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static TextStyle label = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  static TextStyle buttonText = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle mono = const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFamily: 'monospace',
    color: AppColors.textSecondary,
  );
}

// ─── Gradient Background ──────────────────────────────────────────────────

/// Scaffold wrapper with animated gradient mesh background.
class GradientScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  const GradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgGradientStart,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.bgGradientStart,
              AppColors.bgGradientMid,
              AppColors.bgGradientEnd,
              AppColors.bgGradientStart,
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: body,
      ),
    );
  }
}

// ─── Glass Panel ──────────────────────────────────────────────────────────

/// Frosted glass container with backdrop blur and specular highlight.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  final double blur;
  final Color? tint;
  final double? opacity;
  final Color? borderColor;
  final double borderWidth;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.blur = 25,
    this.tint,
    this.opacity,
    this.borderColor,
    this.borderWidth = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final fill = tint ?? Colors.white.withOpacity(opacity ?? 0.07);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? AppColors.glassBorder,
              width: borderWidth,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.glassHighlight,
                fill,
              ],
              stops: const [0.0, 0.35],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Glass Button ─────────────────────────────────────────────────────────

/// Frosted glass button with haptic feedback and optional accent glow.
class GlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final bool isLoading;
  final bool filled;
  final double borderRadius;

  const GlassButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.color,
    this.isLoading = false,
    this.filled = false,
    this.borderRadius = 14,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.accent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                color: widget.filled
                    ? color.withOpacity(0.85)
                    : color.withOpacity(0.12),
                border: Border.all(
                  color: color.withOpacity(widget.filled ? 0.6 : 0.25),
                ),
                boxShadow: widget.filled
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: widget.isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: widget.filled ? Colors.white : color,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            color: widget.filled ? Colors.white : color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.label,
                          style: AppTextStyles.buttonText.copyWith(
                            color: widget.filled ? Colors.white : color,
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

// ─── Glass Icon Button ────────────────────────────────────────────────────

/// Circular frosted glass icon button with haptic.
class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final bool isActive;
  final Color? activeColor;
  final String? tooltip;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.color,
    this.size = 44,
    this.isActive = false,
    this.activeColor,
    this.tooltip,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.isActive
        ? (widget.activeColor ?? AppColors.accent)
        : (widget.color ?? AppColors.textSecondary);

    final child = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isActive
                    ? effectiveColor.withOpacity(0.18)
                    : Colors.white.withOpacity(0.07),
                border: Border.all(
                  color: widget.isActive
                      ? effectiveColor.withOpacity(0.35)
                      : Colors.white.withOpacity(0.12),
                ),
                boxShadow: widget.isActive
                    ? [
                        BoxShadow(
                          color: effectiveColor.withOpacity(0.2),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: effectiveColor,
                size: widget.size * 0.45,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

// ─── Glass Text Field ─────────────────────────────────────────────────────

/// Frosted glass styled text field.
class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextStyle? style;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.style,
    this.validator,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: TextFormField(
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          style: style ?? AppTextStyles.body,
          validator: validator,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            labelText: labelText,
            hintStyle: AppTextStyles.caption,
            labelStyle: AppTextStyles.label.copyWith(color: AppColors.accentSoft),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: AppColors.accent.withOpacity(0.5), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: AppColors.danger.withOpacity(0.5)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.danger),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────

/// A subtle section label for grouped content.
class SectionHeader extends StatelessWidget {
  final String title;
  
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.label.copyWith(
          letterSpacing: 1.2,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── Badge Dot ────────────────────────────────────────────────────────────

/// A small red notification badge dot.
class BadgeDot extends StatelessWidget {
  final bool show;
  final Widget child;

  const BadgeDot({super.key, required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (show)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bgGradientStart, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
