import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fade Call palette: barbershop forest green, charcoal and brass on cream.
abstract final class Palette {
  static const forest = Color(0xFF0F3D2E);
  static const forestDeep = Color(0xFF0A2A20);
  static const forestSoft = Color(0xFFD7E7DD);
  static const charcoal = Color(0xFF1C1F1E);
  static const brass = Color(0xFFC8963E);
  static const brassSoft = Color(0xFFF4E6C8);
  static const cream = Color(0xFFF7F3EA);
  static const sand = Color(0xFFEDE6D7);
  static const ink = Color(0xFF5A605C);
  static const line = Color(0xFFDED6C6);

  static const pass = Color(0xFF237A4B);
  static const passSoft = Color(0xFFDDF0E3);
  static const review = Color(0xFFB4740F);
  static const reviewSoft = Color(0xFFFBEBCF);
  static const fail = Color(0xFFB3362B);
  static const failSoft = Color(0xFFF8DEDA);
}

/// Pass / review / fail colours used for checks, verdicts and statuses.
@immutable
final class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.pass,
    required this.passContainer,
    required this.review,
    required this.reviewContainer,
    required this.fail,
    required this.failContainer,
  });

  final Color pass;
  final Color passContainer;
  final Color review;
  final Color reviewContainer;
  final Color fail;
  final Color failContainer;

  static const light = StatusColors(
    pass: Palette.pass,
    passContainer: Palette.passSoft,
    review: Palette.review,
    reviewContainer: Palette.reviewSoft,
    fail: Palette.fail,
    failContainer: Palette.failSoft,
  );

  @override
  StatusColors copyWith({
    Color? pass,
    Color? passContainer,
    Color? review,
    Color? reviewContainer,
    Color? fail,
    Color? failContainer,
  }) => StatusColors(
    pass: pass ?? this.pass,
    passContainer: passContainer ?? this.passContainer,
    review: review ?? this.review,
    reviewContainer: reviewContainer ?? this.reviewContainer,
    fail: fail ?? this.fail,
    failContainer: failContainer ?? this.failContainer,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      pass: Color.lerp(pass, other.pass, t)!,
      passContainer: Color.lerp(passContainer, other.passContainer, t)!,
      review: Color.lerp(review, other.review, t)!,
      reviewContainer: Color.lerp(reviewContainer, other.reviewContainer, t)!,
      fail: Color.lerp(fail, other.fail, t)!,
      failContainer: Color.lerp(failContainer, other.failContainer, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  StatusColors get status =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}

/// Spacing scale.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

const _scheme = ColorScheme(
  brightness: Brightness.light,
  primary: Palette.forest,
  onPrimary: Palette.cream,
  primaryContainer: Palette.forestSoft,
  onPrimaryContainer: Palette.forestDeep,
  secondary: Palette.brass,
  onSecondary: Palette.charcoal,
  secondaryContainer: Palette.brassSoft,
  onSecondaryContainer: Color(0xFF4A3510),
  tertiary: Color(0xFF6E4B2A),
  onTertiary: Colors.white,
  error: Palette.fail,
  onError: Colors.white,
  errorContainer: Palette.failSoft,
  onErrorContainer: Color(0xFF5C120C),
  surface: Palette.cream,
  onSurface: Palette.charcoal,
  onSurfaceVariant: Palette.ink,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Color(0xFFFBF8F2),
  surfaceContainer: Color(0xFFF2EDE2),
  surfaceContainerHigh: Palette.sand,
  surfaceContainerHighest: Color(0xFFE5DDCC),
  outline: Color(0xFFA7A89E),
  outlineVariant: Palette.line,
  inverseSurface: Palette.charcoal,
  onInverseSurface: Palette.cream,
  inversePrimary: Color(0xFF9CCDB2),
  shadow: Colors.black,
  scrim: Colors.black,
);

/// Builds the app theme. Tests pass `googleFonts: false` to avoid fetching
/// fonts over the network.
ThemeData buildTheme({bool googleFonts = true}) {
  final base = ThemeData(useMaterial3: true, colorScheme: _scheme);
  final body = googleFonts
      ? GoogleFonts.manropeTextTheme(base.textTheme)
      : base.textTheme;
  TextStyle? display(TextStyle? s, {FontWeight weight = FontWeight.w600}) {
    final styled = s?.copyWith(fontWeight: weight, letterSpacing: -0.4);
    return googleFonts ? GoogleFonts.fraunces(textStyle: styled) : styled;
  }

  final textTheme = body
      .copyWith(
        displayLarge: display(body.displayLarge),
        displayMedium: display(body.displayMedium),
        displaySmall: display(body.displaySmall),
        headlineLarge: display(body.headlineLarge),
        headlineMedium: display(body.headlineMedium),
        headlineSmall: display(body.headlineSmall),
        titleLarge: display(body.titleLarge),
        titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: body.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        bodyMedium: body.bodyMedium?.copyWith(height: 1.45),
        bodyLarge: body.bodyLarge?.copyWith(height: 1.45),
      )
      .apply(bodyColor: Palette.charcoal, displayColor: Palette.charcoal);

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  const buttonSize = Size(64, 52);

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: Palette.cream,
    extensions: const [StatusColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.cream,
      foregroundColor: Palette.charcoal,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Palette.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        shape: rounded,
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: rounded,
        foregroundColor: Palette.forest,
        side: const BorderSide(color: Palette.forest, width: 1.2),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.forest,
        textStyle: textTheme.labelLarge,
        shape: rounded,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.forest, width: 1.6),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Palette.sand,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette.brassSoft,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Palette.forestDeep,
      indicatorColor: Palette.brass,
      selectedIconTheme: const IconThemeData(color: Palette.charcoal),
      unselectedIconTheme: const IconThemeData(color: Color(0xFFB9CFC2)),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: Palette.cream,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: const Color(0xFFB9CFC2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Palette.forest,
        selectedForegroundColor: Palette.cream,
        side: const BorderSide(color: Palette.line),
        textStyle: textTheme.labelLarge,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.charcoal,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Palette.cream),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.cream,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Palette.cream,
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.forest,
      linearTrackColor: Palette.sand,
    ),
  );
}
