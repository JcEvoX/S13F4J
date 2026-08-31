import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/note_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/home/home_page.dart';

void main() {
  runApp(const SaltNoteApp());
}

class SaltNoteApp extends StatelessWidget {
  const SaltNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
      ],
      child: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return MaterialApp(
      title: 'NotePad',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.themeMode,
      home: const HomePage(),
    );
  }
}