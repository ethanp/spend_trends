import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/features/trends/category_trend_distribution.dart';
import 'package:spend_trends/features/trends/trend_value_scale.dart';

/// Shared stroke/mark drawing for whiskers and the symbol key.
class DistributionWhiskerMarks._() {
  static void paintRangeStem(
    Canvas canvas, {
    required Offset top,
    required Offset bottom,
    required Color color,
    double strokeWidth = 1.5,
    double capHalfWidth = 5,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(top, bottom, paint);
    canvas.drawLine(
      Offset(top.dx - capHalfWidth, top.dy),
      Offset(top.dx + capHalfWidth, top.dy),
      paint,
    );
    canvas.drawLine(
      Offset(bottom.dx - capHalfWidth, bottom.dy),
      Offset(bottom.dx + capHalfWidth, bottom.dy),
      paint,
    );
  }

  static void paintMedianTick(
    Canvas canvas, {
    required Offset center,
    required Color color,
    double halfWidth = 7,
    double strokeWidth = 1.5,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - halfWidth, center.dy),
      Offset(center.dx + halfWidth, center.dy),
      paint,
    );
  }

  static void paintAverageCross(
    Canvas canvas, {
    required Offset center,
    required Color color,
    double arm = 4,
    double strokeWidth = 1.5,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - arm, center.dy - arm),
      Offset(center.dx + arm, center.dy + arm),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - arm, center.dy + arm),
      Offset(center.dx + arm, center.dy - arm),
      paint,
    );
  }

  static void paintNowDot(
    Canvas canvas, {
    required Offset center,
    required Color color,
    double radius = 3.5,
    Color? ringColor,
  }) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    if (ringColor != null) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }
}

/// Vertical min–max whisker with median tick, avg cross, and current dot.
class DistributionWhiskerPainter({
  required final CategoryTrendDistribution distribution,
  required final TrendValueScale scale,
  required final Color seriesColor,
  required final bool isDimmed,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final color = isDimmed ? EColors.textMuted : seriesColor;
    final stemColor = color.withValues(alpha: isDimmed ? 0.45 : 0.85);

    final centerX = size.width / 2;
    final minY = scale.yFromWhiskerBandTop(distribution.minCents, size.height);
    final maxY = scale.yFromWhiskerBandTop(distribution.maxCents, size.height);
    final medianY = scale.yFromWhiskerBandTop(
      distribution.medianCents,
      size.height,
    );
    final averageY = scale.yFromWhiskerBandTop(
      distribution.averageCents,
      size.height,
    );
    final currentY = scale.yFromWhiskerBandTop(
      distribution.currentCents,
      size.height,
    );

    DistributionWhiskerMarks.paintRangeStem(
      canvas,
      top: Offset(centerX, maxY),
      bottom: Offset(centerX, minY),
      color: stemColor,
    );
    DistributionWhiskerMarks.paintMedianTick(
      canvas,
      center: Offset(centerX, medianY),
      color: color,
    );
    DistributionWhiskerMarks.paintAverageCross(
      canvas,
      center: Offset(centerX, averageY),
      color: color,
    );
    DistributionWhiskerMarks.paintNowDot(
      canvas,
      center: Offset(centerX, currentY),
      color: color,
      ringColor: isDimmed ? null : EColors.backgroundLift,
    );
  }

  @override
  bool shouldRepaint(covariant DistributionWhiskerPainter oldDelegate) {
    return oldDelegate.distribution != distribution ||
        oldDelegate.scale.maxCents != scale.maxCents ||
        oldDelegate.seriesColor != seriesColor ||
        oldDelegate.isDimmed != isDimmed;
  }
}

enum DistributionWhiskerGlyph() {
  range,
  median,
  average,
  now,
}

class _WhiskerMarkPainter(
  final DistributionWhiskerGlyph glyph,
  final Color color,
) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    switch (glyph) {
      case DistributionWhiskerGlyph.range:
        DistributionWhiskerMarks.paintRangeStem(
          canvas,
          top: Offset(center.dx, 2),
          bottom: Offset(center.dx, size.height - 2),
          color: color,
          capHalfWidth: 4,
        );
      case DistributionWhiskerGlyph.median:
        DistributionWhiskerMarks.paintMedianTick(
          canvas,
          center: center,
          color: color,
          halfWidth: 6,
        );
      case DistributionWhiskerGlyph.average:
        DistributionWhiskerMarks.paintAverageCross(
          canvas,
          center: center,
          color: color,
        );
      case DistributionWhiskerGlyph.now:
        DistributionWhiskerMarks.paintNowDot(
          canvas,
          center: center,
          color: color,
          ringColor: EColors.surface,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _WhiskerMarkPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

/// Dashed horizontals at each readable Y tick of the shared whisker scale.
class const DistributionWhiskerGridPainter({
  required final TrendValueScale scale,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EColors.border.withValues(alpha: 0.7)
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;
    for (final tickCents in scale.tickCents) {
      if (tickCents <= 0) continue;
      final y = scale.yFromWhiskerBandTop(tickCents, size.height);
      _strokeDashedValueTick(canvas, y: y, width: size.width, paint: paint);
    }
  }

  void _strokeDashedValueTick(
    Canvas canvas, {
    required double y,
    required double width,
    required Paint paint,
    double dashLength = 4,
    double gapLength = 3,
  }) {
    var x = 0.0;
    var drawingDash = true;
    while (x < width) {
      final next = drawingDash ? x + dashLength : x + gapLength;
      final end = next > width ? width : next;
      if (drawingDash) {
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      }
      x = end;
      drawingDash = !drawingDash;
    }
  }

  @override
  bool shouldRepaint(covariant DistributionWhiskerGridPainter oldDelegate) =>
      oldDelegate.scale.maxCents != scale.maxCents ||
      oldDelegate.scale.tickCents.length != scale.tickCents.length;
}

/// Compact key explaining whisker marks (range / med / avg / now).
class const DistributionWhiskerSymbolKey() extends StatelessWidget {
  static const _entries = <(DistributionWhiskerGlyph, String)>[
    (DistributionWhiskerGlyph.range, 'min–max'),
    (DistributionWhiskerGlyph.median, 'median'),
    (DistributionWhiskerGlyph.average, 'avg'),
    (DistributionWhiskerGlyph.now, 'now'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: ELayout.spaceSm,
        vertical: ELayout.spaceXs,
      ),
      decoration: BoxDecoration(
        color: EColors.surface.withValues(alpha: 0.65),
        borderRadius: ELayout.borderRadiusSm,
        border: Border.all(color: EColors.border.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: ELayout.spaceMd,
            runSpacing: ELayout.spaceXs,
            children: [
              for (final entry in _entries)
                _keyItem(glyph: entry.$1, label: entry.$2),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pair: all-time (left) · past year (right)',
            style: EText.caption.copyWith(
              color: EColors.textMuted,
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyItem({
    required DistributionWhiskerGlyph glyph,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: glyph == DistributionWhiskerGlyph.range ? 12 : 14,
          height: glyph == DistributionWhiskerGlyph.range ? 16 : 14,
          child: CustomPaint(
            painter: _WhiskerMarkPainter(glyph, EColors.textSecondary),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: EText.caption.copyWith(
            color: EColors.textMuted,
            fontSize: 11,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
