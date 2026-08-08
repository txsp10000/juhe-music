import 'package:flutter/material.dart';
import '../theme/app_design_tokens.dart';

class SwipeActionCell extends StatefulWidget {
  final Widget child;
  final String actionLabel;
  final Color actionColor;
  final VoidCallback onAction;

  const SwipeActionCell(
      {super.key,
      required this.child,
      required this.actionLabel,
      required this.actionColor,
      required this.onAction});

  @override
  State<SwipeActionCell> createState() => _SwipeActionCellState();
}

class _SwipeActionCellState extends State<SwipeActionCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isOpen = false;
  static _SwipeActionCellState? _currentOpen;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    if (_currentOpen == this) _currentOpen = null;
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.reverse();
    _isOpen = false;
    if (_currentOpen == this) _currentOpen = null;
  }

  void _open() {
    _currentOpen?._close();
    _currentOpen = this;
    _controller.forward();
    _isOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    final buttonWidth = 82.0 +
        ((widget.actionLabel.length - 2).clamp(0, 4) as num).toDouble() * 8.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < -300) _open();
              if (details.primaryVelocity! > 300) _close();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: buttonWidth,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Transform.translate(
                          offset:
                              Offset(buttonWidth * (1 - _controller.value), 0),
                          child: child),
                      child: ColoredBox(
                        color: widget.actionColor.withValues(alpha: 0.82),
                        child: GestureDetector(
                          onTap: () {
                            if (_isOpen) {
                              widget.onAction();
                              _close();
                            }
                          },
                          child: Center(
                              child: Text(widget.actionLabel,
                                  style: AppDesignTokens.body(
                                      size: 15, weight: FontWeight.w900))),
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Transform.translate(
                        offset: Offset(-buttonWidth * _controller.value, 0),
                        child: child),
                    child: widget.child,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
