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
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.2, 0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx < -2 && !_isOpen) {
      _controller.forward();
      setState(() => _isOpen = true);
    } else if (details.delta.dx > 2 && _isOpen) {
      _controller.reverse();
      setState(() => _isOpen = false);
    }
  }

  void _close() {
    _controller.reverse();
    setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  _close();
                  widget.onAction();
                },
                child: Container(
                  width: 80,
                  alignment: Alignment.center,
                  color: widget.actionColor,
                  child: Text(
                    widget.actionLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        SlideTransition(
          position: _slideAnimation,
          child: GestureDetector(
            onHorizontalDragUpdate: _handleDragUpdate,
            onTap: _isOpen ? _close : null,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
