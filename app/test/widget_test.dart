import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/app.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/theme_provider.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = SecureStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(prefs),
        child: SuperApp(storage: storage),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
