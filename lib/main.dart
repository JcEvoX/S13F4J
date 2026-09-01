import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/backup_service.dart';
import 'state/note_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动周期自动备份（应用运行期间）。
  AutoBackupService.instance.start();
  runApp(const NotePadApp());
}

class NotePadApp extends StatelessWidget {
  const NotePadApp({super.key});

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