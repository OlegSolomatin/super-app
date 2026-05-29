import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/theme_provider.dart';
import 'core/router.dart';
import 'core/secure_storage.dart';

class SuperApp extends StatelessWidget {
  final SecureStorage storage;

  const SuperApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    final appRouter = AppRouter(storage);

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp.router(
          title: 'Super App',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          routerConfig: appRouter.router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
