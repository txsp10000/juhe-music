import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv_tokens.dart';

class TvFocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final FutureOr<void> Function()? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double focusedScale;

  const TvFocusCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
    this.radius = TvTokens.radius,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.focusedScale = 1.02,
  });

  @override
  State<TvFocusCard> createState() => _TvFocusCardState();
}

class _TvFocusCardState extends State<TvFocusCard> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _setFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant TvFocusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _setFocusNode(widget.focusNode);
    }
  }

  void _setFocusNode(FocusNode? focusNode) {
    _ownsFocusNode = focusNode == null;
    _focusNode = focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onTap?.call();
  }

  KeyEventResult _handleConfirmKey(KeyEvent event) {
    final isConfirm = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space;
    if (!isConfirm) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (widget.onLongPress == null) {
      if (event is KeyDownEvent) {
        _activate();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _longPressTriggered = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 800), () async {
        if (!mounted) return;
        _longPressTriggered = true;
        await widget.onLongPress!();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _longPressTimer?.cancel();
      if (!_longPressTriggered) _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: enabled,
      autofocus: widget.autofocus,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        final result = widget.onKeyEvent?.call(node, event);
        if (result != null && result != KeyEventResult.ignored) return result;
        return _handleConfirmKey(event);
      },
      child: AnimatedScale(
        scale: _focused ? widget.focusedScale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.color ?? Colors.transparent,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: _focused
                  ? TvTokens.focus
                  : (widget.borderColor ?? Colors.transparent),
              width: _focused ? 3 : 1,
            ),
          ),
          child: IconTheme(
            data: const IconThemeData(),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: TvTokens.text),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? _activate : null,
                onLongPress: widget.onLongPress == null
                    ? null
                    : () async => widget.onLongPress!(),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
