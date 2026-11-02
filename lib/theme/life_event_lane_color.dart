import 'package:flutter/painting.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/theme/finance_colors.dart';

extension LifeEventLaneColor on LifeEventLane {
  Color get color => switch (this) {
    LifeEventLane.housing => FinanceColors.housing,
    LifeEventLane.job => FinanceColors.job,
    LifeEventLane.milestones => FinanceColors.accentSecondary,
    LifeEventLane.children => const Color(0xFFF28AB2),
  };

  /// Mild per-era accent for labels/edges — tiny hue nudge, odd eras slightly
  /// darker. Fills alternate solid vs hatch (not by brightness).
  Color eraAccent(int eraIndex) {
    final base = HSLColor.fromColor(color);
    final hueShift = switch (eraIndex % 5) {
      0 => -8.0,
      1 => 0.0,
      2 => 10.0,
      3 => -4.0,
      _ => 5.0,
    };
    final hue = (base.hue + hueShift) % 360.0;
    final shifted = base.withHue(hue < 0 ? hue + 360.0 : hue);
    if (eraIndex.isEven) return shifted.toColor();
    return shifted
        .withLightness((shifted.lightness - 0.04).clamp(0.0, 1.0))
        .toColor();
  }
}
