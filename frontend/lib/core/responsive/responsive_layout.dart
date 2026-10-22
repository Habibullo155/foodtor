import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 window size classes.
/// https://m3.material.io/foundations/layout/applying-layout/window-size-classes
enum ScreenSize {
  compact, // < 600   — телефон
  medium, // 600–839  — планшет / узкое окно
  expanded; // ≥ 840  — ПК / широкий веб

  static ScreenSize fromWidth(double width) => switch (width) {
    < 600 => compact,
    < 840 => medium,
    _ => expanded,
  };

  int get gridColumns => switch (this) {
    compact => 2,
    medium => 3,
    expanded => 5,
  };
}

extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize =>
      ScreenSize.fromWidth(MediaQuery.sizeOf(this).width);
  bool get isCompact => screenSize == ScreenSize.compact;

  /// Есть ли мышь — включаем hover-эффекты (web/desktop), не полагаясь только на ширину.
  bool get hasPointer =>
      kIsWeb ||
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);
}

/// Выбирает layout по ширине *доступного пространства* (LayoutBuilder), а не экрана —
/// поэтому корректно работает и внутри split-view, и при ресайзе окна на десктопе.
/// Смена layout'а анимирована (AnimatedSwitcher), без «прыжка».
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  final WidgetBuilder compact;
  final WidgetBuilder? medium;
  final WidgetBuilder? expanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ScreenSize.fromWidth(constraints.maxWidth);
        final builder = switch (size) {
          ScreenSize.expanded => expanded ?? medium ?? compact,
          ScreenSize.medium => medium ?? compact,
          ScreenSize.compact => compact,
        };
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          child: KeyedSubtree(key: ValueKey(size), child: builder(context)),
        );
      },
    );
  }
}
