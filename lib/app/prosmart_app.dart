import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class ProsmartApp extends ConsumerWidget {
  const ProsmartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    const primary = Color(0xFF253444);
    const border = Color(0xFFD8DEE6);
    const bg = Color(0xFFF5F7FA);
    const text = Color(0xFF24313D);
    const accent = Color(0xFF168D7C);

    return MaterialApp.router(
      title: 'Prosmart',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        fontFamilyFallback: const ['Inter', 'Segoe UI', 'Arial'],
        visualDensity: VisualDensity.compact,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          secondary: accent,
          tertiary: const Color(0xFF8FD3C7),
          surface: Colors.white,
          onSurface: text,
        ),
        textTheme: const TextTheme(
          bodySmall: TextStyle(fontSize: 12, color: text),
          bodyMedium: TextStyle(fontSize: 13, color: text),
          bodyLarge: TextStyle(fontSize: 14, color: text),
          titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text),
          headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: text),
          headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: text),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: border),
          ),
        ),
        dividerTheme: const DividerThemeData(color: border, thickness: 1),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Color(0xFFBA1A1A)),
          ),
          labelStyle: TextStyle(color: text),
        ),
        listTileTheme: const ListTileThemeData(
          dense: true,
          iconColor: primary,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        ),
        dataTableTheme: const DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(primary),
          headingTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          dataTextStyle: TextStyle(fontSize: 12, color: text),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            side: const BorderSide(color: border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      routerConfig: router,
    );
  }
}
