import 'dart:math' as math;
import 'package:flutter/material.dart';

class SoundHalo extends StatelessWidget {
  final Color color;
  final double size;
  final double intensity;
  final Widget? child;

  const SoundHalo({
    super.key,
    required this.color,
    this.size = 220,
    this.intensity = 1,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SoundHaloPainter(color: color, intensity: intensity),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _SoundHaloPainter extends CustomPainter {
  final Color color;
  final double intensity;

  const _SoundHaloPainter({required this.color, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.48);
    final radius = math.min(size.width, size.height) / 2;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(0.28 * intensity),
          color.withOpacity(0.08 * intensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = color.withOpacity(0.22 * intensity);
    canvas.drawOval(Rect.fromCenter(center: center, width: size.width * 0.86, height: size.height * 0.58), ringPaint);

    final ringPaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withOpacity(0.09 * intensity);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.34);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawOval(Rect.fromCenter(center: center, width: size.width * 0.72, height: size.height * 0.42), ringPaint2);
    canvas.restore();

    final tickPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.30 * intensity);
    for (var i = 0; i < 20; i++) {
      final angle = -math.pi * 0.85 + i * math.pi * 1.7 / 19;
      if (i % 3 == 1) continue;
      final inner = radius * (0.72 + (i % 4) * 0.015);
      final outer = inner + 7 + (i % 5);
      final p1 = center + Offset(math.cos(angle) * inner, math.sin(angle) * inner * 0.72);
      final p2 = center + Offset(math.cos(angle) * outer, math.sin(angle) * outer * 0.72);
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoundHaloPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.intensity != intensity;
  }
}

class MiniWave extends StatefulWidget {
  final bool playing;
  final Color color;
  final double size;

  const MiniWave({super.key, required this.playing, required this.color, this.size = 22});

  @override
  State<MiniWave> createState() => _MiniWaveState();
}

class _MiniWaveState extends State<MiniWave> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 860));
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant MiniWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value * 2 * math.pi;
        final heights = [
          widget.size * (0.34 + 0.28 * math.sin(t).abs()),
          widget.size * (0.44 + 0.34 * math.sin(t + 1.8).abs()),
          widget.size * (0.28 + 0.24 * math.sin(t + 3.4).abs()),
        ];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            return Container(
              width: 3,
              height: heights[i].clamp(5.0, widget.size),
              margin: const EdgeInsets.symmetric(horizontal: 1.6),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        );
      },
    );
  }
}
