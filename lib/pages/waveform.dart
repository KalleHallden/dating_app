import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaveformWidget extends CustomPainter {
  final List<double> spectrumData;

  WaveformWidget(this.spectrumData);

  @override
  void paint(Canvas canvas, Size size) {
    const double maxBarHeight = 80.0;
    final double centerY = size.height / 2;

    final Paint paint = Paint()
      ..color = const Color(0xFF985021)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Use spectrum data or fallback to silent state
    final data = spectrumData.isNotEmpty
        ? spectrumData
        : List.generate(13, (index) => 0.0);
    final numberOfBars = data.length;

    // 70% of the total width for the waveform
    final double waveformWidth = size.width * 0.7;
    final double offsetX = (size.width - waveformWidth) / 2;
    final double barSpacing = waveformWidth / (numberOfBars - 1);

    // Draw individual bars based on spectrum data
    for (int i = 0; i < numberOfBars; i++) {
      final double x = offsetX + barSpacing * i;

      // Get the spectrum value for this bar (0.0 to 1.0)
      double barValue = data[i].clamp(0.0, 1.0);

      // Apply some smoothing and minimum height for visual appeal
      final double minHeight = 2.0;
      final double barHeight = math.max(minHeight, barValue * maxBarHeight);

      // Add slight animation curve for more natural movement
      final double smoothedHeight =
          _applySmoothingCurve(barHeight / maxBarHeight) * maxBarHeight;

      // Draw the bar as a vertical line
      final path = Path();
      path.moveTo(x, centerY - smoothedHeight / 2);
      path.lineTo(x, centerY + smoothedHeight / 2);

      // Vary the color intensity based on the bar height for visual interest
      final colorIntensity =
          (smoothedHeight / maxBarHeight * 0.7 + 0.3).clamp(0.3, 1.0);
      paint.color = Colors.white.withOpacity(colorIntensity);

      canvas.drawPath(path, paint);
    }
  }

  /// Apply a smoothing curve to make the animation more natural
  double _applySmoothingCurve(double value) {
    // Use an ease-out curve for more natural bar movement
    return (1 - math.pow(1 - value, 2)).toDouble();
  }

  @override
  bool shouldRepaint(covariant WaveformWidget oldDelegate) {
    // Check if spectrum data has changed
    if (oldDelegate.spectrumData.length != spectrumData.length) {
      return true;
    }

    for (int i = 0; i < spectrumData.length; i++) {
      if ((oldDelegate.spectrumData[i] - spectrumData[i]).abs() > 0.01) {
        return true;
      }
    }

    return false;
  }
}
