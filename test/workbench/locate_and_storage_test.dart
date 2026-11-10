import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/vault/vault_notes_repository.dart';
import 'package:notepad/services/settings_service.dart';
import 'package:notepad/services/storage_paths.dart';
import 'package:notepad/services/vault_relocator.dart';
import 'package:notepad/state/note_provider.dart';
import 'package:notepad/theme/app_theme.dart';
import 'package:notepad/ui/home/home_page.dart';
import 'package:notepad/ui/settings/storage_location_page.dart';
import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/extensions/core_extension.dart';
import 'package:notepad/workbench/extensions/notes_extension.dart';
import 'package:notepad/workbench/services/extension_host.dart';
import 'package:notepad/workbench/services/quick_open.dart';
import 'package:notepad/workbench/services/workbench.dart';
import 'package:notepad/workbench/ui/workbench_page.dart';
import 'package:notepad/plugins/builtin_plugins.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/documents';
  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
  @override
  Future<String?> getExternalStoragePath() async => null;
}

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('公共文档目录', () {
    test('由应用专属外部目录推出 Documents/NotePad', () {
      expect(
        StoragePaths.publicVaultRootFrom(
            '/storage/emulated/0/Android/data/com.example.notepad/files'),
        '/storage/emulated/0/Documents/NotePad',
      );
      expect(
        StoragePaths.publicVaultRootFrom(
            '/storage/1234-ABCD/Android/data/x/files'),
        '/storage/1234-ABCD/Documents/NotePad',
      );
      expect(StoragePaths.publicVaultRootFrom('/data/user/0/x/files'), isNull);
    });

    test('存储位置设置：默认未设置，写入后可读回', () async {
      final settings = await SettingsService.instance;
      expect(settings.storageLocation, isNull);
      await settings.setStorageLocation(StorageLocation.documents);
      expect(settings.storageLocation, StorageLocation.documents);
    });
  });

  group('VaultRelocator', () {
    late Directory temp;
    setUp(() async => temp = await Directory.systemTemp.createTemp('reloc_'));
    tearDown(() => temp.delete(recursive: true));

    Future<String> seed(String name) async {
      final root = '${temp.path}/$name';
      await Directory('$root/工作').create(recursive: true);
      await File('$root/tree.json').writeAsString('{}');
      await File('$root/工作/周报.md').writeAsString('本周完成');
      return root;
    }

    test('复制整个目录，源目录保持不变，不留临时目录', () async {
      final from = await seed('a');
      final to = '${temp.path}/Documents/NotePad';
      final result = await VaultRelocator.copyVault(from, to);
      expect(result.copiedFiles, 2);
      expect(await File('$to/工作/周报.md').readAsString(), '本周完成');
      expect(await File('$from/工作/周报.md').exists(), isTrue);
      expect(Directory('$to.migrating').existsSync(), isFalse);
    });

    test('目标已有内容：沿用目标，不覆盖', () async {
      final from = await seed('a');
      final to = await seed('b');
      await File('$to/工作/周报.md').writeAsString('目标里的版本');
      final result = await VaultRelocator.copyVault(from, to);
      expect(result.targetAlreadyHadData, isTrue);
      expect(await File('$to/工作/周报.md').readAsString(), '目标里的版本');
    });

    test('源目录不存在（全新安装）：只创建目标', () async {
      final to = '${temp.path}/new';
      final result = await VaultRelocator.copyVault('${temp.path}/none', to);
      expect(result.sourceMissing, isTrue);
      expect(Directory(to).existsSync(), isTrue);
    });
  });

  testWidgets('存储位置页：非 Android 只提供应用目录；确定后写入设置并回调', (tester) async {
    final temp = await tester
        .runAsync(() => Directory.systemTemp.createTemp('storage_page_'));
    addTearDown(() => tester.runAsync(() => temp!.delete(recursive: true)));
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(temp!.path);
    addTearDown(() => PathProviderPlatform.instance = original);

    final settings = (await tester.runAsync(() => SettingsService.instance))!;
    StorageLocation? done;
    await tester.pumpWidget(MaterialApp(
      home: StorageLocationPage(
        settings: settings,
        onDone: (location, message) => done = location,
      ),
    ));
    await _settle(tester, rounds: 3);
    expect(find.byKey(const ValueKey('storage-documents')), findsNothing);
    expect(find.byKey(const ValueKey('storage-internal')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('storage-apply')));
    await _waitFor(tester, find.byType(StorageLocationPage));
    for (var i = 0; i < 40 && done == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, StorageLocation.internal);
    expect(settings.storageLocation, StorageLocation.internal);

    final paths = (await tester.runAsync(StoragePaths.resolve))!;
    expect(paths.vaultRoot, '${temp.path}/documents/Notepad');
    expect(Directory(paths.vaultRoot).existsSync(), isTrue);
  });

  group('定位最后编辑的文章', () {
    late Directory temp;
    late VaultNotesRepository repo;

    Future<void> openRepo(WidgetTester tester) async {
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('locate_');
        repo = VaultNotesRepository.atRoot(temp.path);
        await repo.init();
      });
      addTearDown(() => tester.runAsync(() async {
            await repo.close();
            await temp.delete(recursive: true);
          }));
    }

    testWidgets('编辑器关闭 / 重启应用后仍能找回最后编辑的文章', (tester) async {
      await openRepo(tester);
      final id = (await tester.runAsync(() async {
        final folder = await repo.createNode(isFolder: true, title: '工作');
        final note = await repo.createNode(
            isFolder: false, title: '周报', parentId: folder.id, content: 'x');
        return note.id;
      }))!;

      final first = NoteProvider(repository: repo);
      expect(await tester.runAsync(first.locateTargetId), isNull);
      await tester.runAsync(() => first.markEdited(id));
      expect(first.currentEditingNodeId, isNull);
      expect(await tester.runAsync(first.locateTargetId), id);

      final restarted = NoteProvider(repository: repo);
      expect(await tester.runAsync(restarted.locateTargetId), id);
    });

    testWidgets('首页速拨「定位」：没有正在编辑的文章时回到最后编辑的那一篇', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openRepo(tester);
      final ids = (await tester.runAsync(() async {
        final folder = await repo.createNode(isFolder: true, title: '工作');
        final note = await repo.createNode(
            isFolder: false, title: '周报', parentId: folder.id, content: 'x');
        return [folder.id, note.id];
      }))!;
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('note.lastEditedNodeId', ids[1]);
      });

      late NoteProvider provider;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => provider = NoteProvider(repository: repo),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const HomePage()),
        ),
      );
      await _settle(tester);
      expect(provider.currentParentId, isNull);

      await tester.tap(find.byIcon(Icons.add));
      await _settle(tester, rounds: 3);
      await tester.tap(find.byIcon(Icons.edit_location_outlined));
      await _waitFor(tester, find.text('周报'));
      await _settle(tester, rounds: 3);

      expect(provider.currentParentId, ids[0]);
      expect(find.text('周报'), findsOneWidget);
    });
  });

  testWidgets('工作台：在资源管理器中定位当前文件（展开祖先目录并选中）', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory temp;
    late VaultNotesRepository repo;
    late Workbench workbench;
    late ExtensionHost host;
    late QuickOpenService quickOpen;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('reveal_');
      repo = VaultNotesRepository.atRoot(temp.path);
      await repo.init();
      final folder = await repo.createNode(isFolder: true, title: '工作');
      final sub =
          await repo.createNode(isFolder: true, title: '周报', parentId: folder.id);
      await repo.createNode(
          isFolder: false, title: '第一周', parentId: sub.id, content: '内容');
      workbench = Workbench(sessionStore: MemorySessionStore());
      host = ExtensionHost(workbench)
        ..registerFactory(kCorePluginId, CoreExtension.new)
        ..registerFactory('note.editor', () => NotesExtension(repo))
        ..registerAlwaysOn(coreExtensionInfo());
      workbench.workspaceFolderSource = () async => [
            const WorkspaceFolder(
                scheme: 'notes', name: '笔记', state: 'active'),
          ];
      quickOpen = QuickOpenService(workbench);
      final m = builtinNotesPlugin();
      await host.sync([
        PluginInfo(
          id: m.id,
          capability: m.capability,
          enabled: true,
          contributes: m.contributes,
          activationEvents: m.activationEvents,
        ),
      ]);
      await workbench.refreshWorkspace();
    });
    addTearDown(() => tester.runAsync(() async {
          quickOpen.dispose();
          host.dispose();
          workbench.dispose();
          await repo.close();
          await temp.delete(recursive: true);
        }));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NoteProvider(repository: repo)),
          ChangeNotifierProvider<Workbench>.value(value: workbench),
          Provider<QuickOpenService>.value(value: quickOpen),
        ],
        child: const MaterialApp(home: WorkbenchPage()),
      ),
    );
    await _settle(tester);

    final target = ResourceUri.parse('notes:/工作/周报/第一周.md');
    await tester.runAsync(() => workbench.openResource(target));
    await _settle(tester);
    expect(find.text('第一周.md'), findsNothing, reason: '资源管理器尚未展开');

    await tester.runAsync(
        () => workbench.executeCommand('workbench.action.revealActiveFile'));
    await _waitFor(tester, find.text('第一周.md'));
    await _settle(tester);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('第一周.md'), findsWidgets);
    expect(workbench.explorerSelection, target);
    expect(tester.takeException(), isNull);
  });
}
