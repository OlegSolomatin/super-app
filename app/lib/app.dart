import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/secure_storage.dart';

class SuperApp extends StatelessWidget {
  final SecureStorage storage;

  const SuperApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    final appRouter = AppRouter(storage);

    return MaterialApp.router(
      title: 'Super App',
      theme: AppTheme.darkTheme,
      routerConfig: appRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}
