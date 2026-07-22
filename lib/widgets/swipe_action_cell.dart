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
  late final Animation<Offset> _slideAnimation;
  bool _isOpen = false;

  static _SwipeActionCellState? _currentOpen;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(-1.0, 0.0)).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
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
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (_isOpen) {
                  widget.onAction();
                  _close();
                }
              },
              child: Container(
                color: widget.actionColor,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  widget.actionLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          // 前景内容
          SlideTransition(
            position: _slideAnimation,
            child: Container(
              color: const Color(0xFF0D0F14),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
