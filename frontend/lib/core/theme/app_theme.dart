import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Дизайн-токены. Все отступы — кратны 4, радиусы и тени — только отсюда.
abstract final class Insets {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0;
}

abstract final class Radii {
  static const sm = 10.0, md = 14.0, lg = 20.0, pill = 999.0;
}

/// Акцентные цвета — одинаковые в светлой и тёмной теме.
/// Нейтральные (фон, поверхности, текст, границы) — в [AppPalette], читаются через `context.palette`.
abstract final class AppColors {
  static const brand = Color(0xFF0B5D3B); // основной зелёный
  static const accent = Color(0xFF4CAF50); // акцентный зелёный
  static const soft = Color(0xFFE8F5E9); // светло-зелёный фон плашек
  static const cream = Color(0xFFF7F3EA); // доп. цвет — фон страниц
  static const cta = Color(0xFFFFA726); // кнопки
  static const onCta = Color(
    0xFF1F2A1F,
  ); // текст на кнопках (белый на оранжевом плохо читается)
  static const hit = Color(0xFFFB8C00); // «Хит»
  static const fresh = Color(0xFF4CAF50); // «Новинка», «бесплатно»
  static const lowStock = Color(0xFFE53935); // «Осталось мало», скидки
  static const wholesale = Color(0xFF0288D1);
  static const storyRing = [accent, cta, brand];
}

/// Нейтральная палитра темы. ThemeExtension → корректно анимируется при смене темы
/// и создаёт зависимость от Theme: виджеты перерисовываются сами.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.skeleton,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.softShadow,
    required this.liftedShadow,
  });

  final Color background; // фон страницы
  final Color surface; // карточки, панели
  final Color surfaceMuted; // подложка под фото, поля ввода, степперы
  final Color skeleton;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final List<BoxShadow> softShadow;
  final List<BoxShadow> liftedShadow;

  static const light = AppPalette(
    background: Color(0xFFF7F3EA),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF1EDE3),
    skeleton: Color(0xFFEAE5D8),
    border: Color(0xFFE7E1D4),
    textPrimary: Color(0xFF17291F),
    textSecondary: Color(0xFF5E6B62),
    softShadow: [
      BoxShadow(color: Color(0x0A111827), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0F111827), blurRadius: 16, offset: Offset(0, 6)),
    ],
    liftedShadow: [
      BoxShadow(color: Color(0x0F111827), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x1F111827),
        blurRadius: 32,
        offset: Offset(0, 16),
      ),
    ],
  );

  /// Тёмная: не чистый чёрный (#000 режет глаза и «съедает» тени), а графитовые слои.
  static const dark = AppPalette(
    background: Color(0xFF0C1711),
    surface: Color(0xFF13231A),
    surfaceMuted: Color(0xFF1A2D22),
    skeleton: Color(0xFF22382B),
    border: Color(0xFF25392D),
    textPrimary: Color(0xFFEEF5EF),
    textSecondary: Color(0xFF9FB3A6),
    softShadow: [
      BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6)),
    ],
    liftedShadow: [
      BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 32,
        offset: Offset(0, 16),
      ),
    ],
  );

  @override
  AppPalette copyWith({Color? background, Color? surface}) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted,
    skeleton: skeleton,
    border: border,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    softShadow: softShadow,
    liftedShadow: liftedShadow,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      skeleton: c(skeleton, other.skeleton),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      softShadow: BoxShadow.lerpList(softShadow, other.softShadow, t)!,
      liftedShadow: BoxShadow.lerpList(liftedShadow, other.liftedShadow, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

abstract final class AppTheme {
  /// [useGoogleFonts] = false в тестах: google_fonts грузит шрифт по сети.
  static ThemeData light({bool useGoogleFonts = true}) =>
      _build(Brightness.light, AppPalette.light, useGoogleFonts);

  static ThemeData dark({bool useGoogleFonts = true}) =>
      _build(Brightness.dark, AppPalette.dark, useGoogleFonts);

  static ThemeData _build(
    Brightness brightness,
    AppPalette p,
    bool useGoogleFonts,
  ) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
      primary: dark ? const Color(0xFF6BCB77) : AppColors.brand,
      secondary: AppColors.accent,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      outline: p.textSecondary,
      outlineVariant: p.border,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.surfaceMuted,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );
    final TextTheme fontTheme = useGoogleFonts
        ? GoogleFonts.interTextTheme(base.textTheme)
        : base.textTheme;
    final textTheme = fontTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    return base.copyWith(
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hintStyle: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      // Главные кнопки — оранжевые с тёмным текстом (по брендбуку FOODTOR)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.cta,
          foregroundColor: AppColors.onCta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        labelStyle: textTheme.labelLarge,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? p.surfaceMuted : p.textPrimary,
        contentTextStyle: TextStyle(color: dark ? p.textPrimary : p.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    );
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 36,
    this.onDark = false,
    this.subtitle,
  });
  final double size;
  final bool onDark; // на зелёном/тёмном фоне: FOOD — белым
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    final food = onDark || darkTheme ? Colors.white : AppColors.brand;
    final tor = onDark ? const Color(0xFF8BD895) : AppColors.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: onDark
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E8A4C), AppColors.brand],
                  ),
            color: onDark ? Colors.white : null,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Icon(
            Icons.eco_rounded,
            color: onDark ? AppColors.brand : Colors.white,
            size: size * 0.62,
          ),
        ),
        SizedBox(width: size * 0.28),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'FOOD',
                    style: TextStyle(color: food),
                  ),
                  TextSpan(
                    text: 'TOR',
                    style: TextStyle(color: tor),
                  ),
                ],
              ),
              maxLines: 1,
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                height: 1.1,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  color: onDark
                      ? Colors.white70
                      : context.palette.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
