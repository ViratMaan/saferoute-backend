import 'package:flutter/material.dart';

class HoverTranslateCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isActive;
  final Color color;
  final String route;
  const HoverTranslateCard({
    super.key,
    required this.child,
    required this.onTap,
    required this.isActive,
    required this.color,
    required this.route,
  });

  @override
  State<HoverTranslateCard> createState() => _HoverTranslateCardState();
}

class _HoverTranslateCardState extends State<HoverTranslateCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 12),
          // Shifts 4 pixels to the right on desktop cursor hover for a snappy, premium feel
          transform: Matrix4.identity()
            ..setTranslationRaw(_isHovered ? 4.0 : 0.0, 0.0, 0.0),
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFF1E293B)
                : const Color(0xFF151F32),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isActive
                  ? widget.color
                  : (_isHovered
                        ? widget.color.withValues(alpha: 0.5)
                        : const Color(0xFF22314D)),
              width: widget.isActive ? 1.5 : 1,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(-2, 2),
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
