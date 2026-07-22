import 'package:flutter/material.dart';

class SwipeActionCell extends StatefulWidget {
  final Widget child;
  final String actionLabel;
  final Color actionColor;
  final VoidCallback onAction;

  const SwipeActionCell({
    super.key,
    required this.child,
    required this.actionLabel,
    required this.actionColor,
    required this.onAction,
  });

  @override
  State<SwipeActionCell> createState() => _SwipeActionCellState();
}

class _SwipeActionCellState extends State<SwipeActionCell> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isOpen = false;

  static _SwipeActionCellState? _currentOpen;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
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
    final buttonWidth = 80.0 + (widget.actionLabel.length - 2) * 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < -300) {
              _open();
            } else if (details.primaryVelocity! > 300) {
              _close();
            }
          },
          child: Stack(
            children: [
              // 背景按钮
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: buttonWidth,
                child: GestureDetector(
                  onTap: () {
                    if (_isOpen) {
                      widget.onAction();
                      _close();
                    }
                  },
                  child: Container(
                    color: widget.actionColor,
                    alignment: Alignment.center,
                    child: Text(
                      widget.actionLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              // 前景内容，只滑动按钮宽度
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(-_controller.value * buttonWidth, 0),
                    child: child,
                  );
                },
                child: Container(
                  color: const Color(0xFF0D0F14),
                  width: constraints.maxWidth,
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
