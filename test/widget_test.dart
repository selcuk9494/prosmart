// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prosmart/app/prosmart_app.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  testWidgets('Prosmart app opens login', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: ProsmartApp()));
    await tester.pumpAndSettle();

    expect(find.text('Kullanıcı Girişi'), findsOneWidget);
    expect(find.text('Giriş'), findsOneWidget);
    expect(find.text('Demo modunda şifre opsiyonel.'), findsOneWidget);
  });
}
