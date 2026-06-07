import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class ProsmartApp extends ConsumerWidget {
  const ProsmartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    const crmBlue = Color(0xFF3C4E62);
    const crmBorder = Color(0xFFCCCCCC);
    const crmInputBorder = Color(0xFF999999);
    const crmBg = Color(0xFFF4F4F4);
    const crmText = Color(0xFF414141);

    return MaterialApp.router(
      title: 'Prosmart',
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: 'Tahoma',
        fontFamilyFallback: const ['Tahoma', 'Segoe UI', 'Arial'],
        visualDensity: VisualDensity.compact,
        scaffoldBackgroundColor: crmBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: crmBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: crmBlue,
          secondary: crmBlue,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          bodySmall: TextStyle(fontSize: 11, color: crmText),
          bodyMedium: TextStyle(fontSize: 12, color: crmText),
          bodyLarge: TextStyle(fontSize: 13, color: crmText),
          titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: crmText),
          titleMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: crmText),
          titleLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: crmText),
          headlineSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: crmText),
          headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: crmText),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: crmBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: crmBorder),
          ),
        ),
        dividerTheme: const DividerThemeData(color: crmBorder, thickness: 1),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFFAFAFA),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: crmInputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: crmInputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: crmBlue, width: 1.5),
          ),
          labelStyle: TextStyle(color: crmText),
        ),
        listTileTheme: const ListTileThemeData(
          dense: true,
          iconColor: crmBlue,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        ),
        dataTableTheme: const DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(crmBlue),
          headingTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          dataTextStyle: TextStyle(fontSize: 12, color: crmText),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5E5E5),
            foregroundColor: crmText,
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: crmInputBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: crmText,
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            side: const BorderSide(color: crmInputBorder),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: crmBlue,
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
