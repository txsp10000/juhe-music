import 'package:flutter/material.dart';

class TvTokens {
  static const background = Color(0xFF10121A);
  static const playbackBlack = Color(0xFF050706);
  static const panel = Color(0xFF252A36);
  static const panelSoft = Color(0xFF2B3040);
  static const panelElevated = Color(0xFF33394A);
  static const focus = Color(0xFF48D98A);
  static const accent = Color(0xFF48D98A);
  static const text = Color(0xFFF5F7F8);
  static const muted = Color(0xFFA4ABB8);
  static const faint = Color(0xFF656D7B);
  static const danger = Color(0xFFFF7D73);

  static const edge = 68.0;
  static const gap = 22.0;
  static const radius = 28.0;
  static const smallRadius = 18.0;
  static const drawerRadius = 42.0;

  static TextStyle hero({double size = 56}) {
    return TextStyle(
      color: text,
      fontSize: size,
      height: 1.08,
      fontWeight: FontWeight.w800,
    );
  }

  static TextStyle title({double size = 32, Color color = text}) {
    return TextStyle(
      color: color,
      fontSize: size,
      height: 1.1,
      fontWeight: FontWeight.w700,
    );
  }

  static TextStyle body(
      {double size = 22,
      Color color = text,
      FontWeight weight = FontWeight.w600}) {
    return TextStyle(
      color: color,
      fontSize: size,
      height: 1.25,
      fontWeight: weight,
    );
  }

  static TextStyle label({double size = 18, Color color = muted}) {
    return TextStyle(
      color: color,
      fontSize: size,
      height: 1.15,
      fontWeight: FontWeight.w700,
    );
  }
}
