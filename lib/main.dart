import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/migration/legacy_migrator.dart';
import 'data/notes_repository.dart';
import 'data/sqlite_notes_repository.dart';
import 'data/vault/vault_notes_repository.dart';
import 'data/vault/vault_store.dart';
import 'plugins/builtin_plugins.dart';
import 'plugins/plugin_manager.dart';
import 'services/backup_service.dart';
import 'services/namespace_registry.dart';
import 'services/settings_service.dart';
import 'services/storage_paths.dart';
import 'state/note_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化插件系统：注册宿主能力 + 注册内置插件（笔记 / 文件系统）。
  registerBuiltinCapabilities();
  await PluginManager.instance.init();
  PluginManager.instance
    ..registerBuiltin(builtinNotesPlugin())
    ..registerBuiltin(builtinFileBrowserPlugin());
  // 启动时从持久化设置恢复主题模式，保证全局主题与用户选择一致。
  final themeController = await ThemeController.load();
  // 数据后端：默认文件化 vault；失败回退 sqlite。
  final settings = await SettingsService.instance;
  final storagePaths = await StoragePaths.resolve();
  final repository = await _openRepository(settings, storagePaths);
  // 启动周期自动备份（应用运行期间）。
  AutoBackupService.instance
    ..attach(repository)
    ..start();
  runApp(
    NotePadApp(
      themeController: themeController,
      repository: repository,
    ),
  );
}

Future<NotesRepository> _openRepository(
  SettingsService settings,
  StoragePaths paths,
) async {
  if (settings.storageBackend == StorageBackend.sqlite) {
    debugPrint('[Bootstrap] 使用 sqlite 后端');
    final repository = SqliteNotesRepository();
    await repository.init();
    return repository;
  }

  try {
    final store = VaultStore(paths.vaultRoot);
    final repository = VaultNotesRepository(store: store);
    await repository.init();

    final migration = await LegacyMigrator(
      repository: repository,
      vaultPath: paths.vaultRoot,
      dbPath: paths.legacyDbPath,
    ).migrateIfNeeded();
    debugPrint('[Bootstrap] 迁移结果: ${migration.status} ${migration.message ?? ''}');
    if (migration.status == 'failed') {
      throw StateError(migration.message ?? '旧库迁移失败');
    }

    final registry = NamespaceRegistry(store: store);
    await registry.load();
    await registry.ensureNotes();
    debugPrint('[Bootstrap] 使用文件后端: ${paths.vaultRoot}');
    return repository;
  } catch (e) {
    debugPrint('[Bootstrap] 文件后端不可用，回退 sqlite: $e');
    final repository = SqliteNotesRepository();
    await repository.init();
    return repository;
  }
}

class NotePadApp extends StatelessWidget {
  const NotePadApp({
    super.key,
    required this.themeController,
    required this.repository,
  });

  final ThemeController themeController;
  final NotesRepository repository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider(
          create: (_) => NoteProvider(repository: repository),
        ),
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
