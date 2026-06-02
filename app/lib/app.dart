import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            // Escape → назад
            const SingleActivator(LogicalKeyboardKey.escape): () {
              final router = GoRouter.of(context);
              if (router.canPop()) router.pop();
            },
            // Ctrl+1 → главная
            const SingleActivator(
              LogicalKeyboardKey.digit1,
              control: true,
            ): () => GoRouter.of(context).go('/'),
            // Ctrl+2 → трейдинг
            const SingleActivator(
              LogicalKeyboardKey.digit2,
              control: true,
            ): () => GoRouter.of(context).go('/trading'),
            // Ctrl+3 → агенты
            const SingleActivator(
              LogicalKeyboardKey.digit3,
              control: true,
            ): () => GoRouter.of(context).go('/admin/agents'),
            // Ctrl+L → логин
            const SingleActivator(
              LogicalKeyboardKey.keyL,
              control: true,
            ): () => GoRouter.of(context).go('/login'),
          },
          child: Focus(
            autofocus: true,
            child: MaterialApp.router(
              title: 'Super App',
              theme: AppTheme.lightTheme(),
              darkTheme: AppTheme.darkTheme(),
              themeMode: themeProvider.themeMode,
              routerConfig: appRouter.router,
              debugShowCheckedModeBanner: false,
            ),
          ),
        );
      },
    );
  }
}
