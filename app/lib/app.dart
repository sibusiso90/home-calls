import 'package:fade_call/core/theme.dart';
import 'package:fade_call/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FadeCallApp extends ConsumerWidget {
  const FadeCallApp({super.key, this.googleFonts = true});

  final bool googleFonts;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Fade Call',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(googleFonts: googleFonts),
    routerConfig: ref.watch(routerProvider),
  );
}
