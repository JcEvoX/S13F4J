import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/notes_repository.dart';
import 'package:notepad/data/vault/vault_notes_repository.dart';
import 'package:notepad/plugins/builtin_plugins.dart';
import 'package:notepad/plugins/plugin_model.dart';
import 'package:notepad/state/note_provider.dart';
import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/extensions/core_extension.dart';
import 'package:notepad/workbench/extensions/notes_extension.dart';
import 'package:notepad/workbench/services/extension_host.dart';
import 'package:notepad/workbench/services/quick_open.dart';
import 'package:notepad/workbench/services/workbench.dart';
import 'package:notepad/workbench/ui/workbench_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

PluginInfo _info(PluginManifest m, {bool enabled = true}) => PluginInfo(
      id: m.id,
      capability: m.capability,
      enabled: enabled,
      contributes: m.contributes,
      activationEvents: m.activationEvents,
    );

class _Harness {
  _Harness(this.tempDir, this.repo, this.workbench, this.host, this.quickOpen);

  final Directory tempDir;
  final NotesRepository repo;
  final Workbench workbench;
  final ExtensionHost host;
  final QuickOpenService quickOpen;

  Future<void> syncPlugins({bool notes = true}) => host.sync([
        _info(builtinNotesPlugin(), enabled: notes),
      ]);

  Future<void> dispose() async {
    quickOpen.dispose();
    host.dispose();
    workbench.dispose();
    await repo.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  }
}

Future<_Harness> _createHarness(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final tempDir = await Directory.systemTemp.createTemp('notepad_wb_ui_');
    final repo = VaultNotesRepository.atRoot(tempDir.path);
    await repo.init();
    final workbench = Workbench(sessionStore: MemorySessionStore());
    final host = ExtensionHost(workbench)
      ..registerFactory(kCorePluginId, CoreExtension.new)
      ..registerFactory('note.editor', () => NotesExtension(repo))
      ..registerAlwaysOn(coreExtensionInfo());
    workbench.workspaceFolderSource = () async => [
          WorkspaceFolder(
            scheme: 'notes',
            name: '笔记',
            state: host.canActivateFor('onResource:notes') ||
                    host.isActive('builtin.notes')
                ? 'active'
                : 'disabled',
          ),
        ];
    final harness =
        _Harness(tempDir, repo, workbench, host, QuickOpenService(workbench));
    await harness.syncPlugins();
    await workbench.refreshWorkspace();
    return harness;
  }))!;
}

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 真实文件 IO 不在 FakeAsync 里推进：轮询直到 [finder] 出现或超时。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int maxRounds = 150,
}) async {
  for (var i = 0; i < maxRounds; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpPage(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NoteProvider(repository: h.repo)),
        ChangeNotifierProvider<Workbench>.value(value: h.workbench),
        Provider<QuickOpenService>.value(value: h.quickOpen),
      ],
      child: const MaterialApp(home: WorkbenchPage()),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> useSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('宽屏：活动栏 + 资源管理器 + 欢迎页；展开笔记并在标签中编辑', (tester) async {
    await useSize(tester, const Size(1200, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(() async {
      final folder = await h.repo.createNode(isFolder: true, title: '工作');
      await h.repo.createNode(
        isFolder: false,
        title: '周报',
        parentId: folder.id,
        content: '本周完成重构',
      );
    });

    await _pumpPage(tester, h);
    expect(find.text('NotePad 工作台'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-explorer')), findsOneWidget);
    expect(find.text('笔记'), findsWidgets);

    await tester.tap(find.text('笔记').first);
    await _waitFor(tester, find.text('工作'));
    expect(find.text('工作'), findsOneWidget);

    await tester.tap(find.text('工作'));
    await _waitFor(tester, find.text('周报.md'));
    expect(find.text('周报.md'), findsOneWidget);

    await tester.tap(find.text('周报.md'));
    await _waitFor(tester, find.widgetWithText(TextField, '本周完成重构'));
    expect(h.workbench.activeTab!.resource.toString(), 'notes:/工作/周报.md');
    expect(h.workbench.activeTab!.viewType, 'notes.markdown');
    expect(find.widgetWithText(TextField, '本周完成重构'), findsOneWidget);
    expect(h.workbench.contextKeys.get('resourceScheme'), 'notes');

    await tester.tap(find.byTooltip('关闭').last);
    await tester.pump();
    expect(h.workbench.tabs.where((t) => t.resource != null), isEmpty);
  });

  testWidgets('命令面板：> 搜索命令并执行；无前缀按文件名快速打开', (tester) async {
    await useSize(tester, const Size(1200, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(() async {
      await h.repo.createNode(isFolder: false, title: '会议纪要', content: '议程');
    });
    await _pumpPage(tester, h);

    unawaitedRun(
        () => h.workbench.executeCommand('workbench.action.showCommands'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('quick-open-input')), findsOneWidget);
    expect(
      h.quickOpen.findCommands('').map((m) => m.command.command),
      contains('notes.newNote'),
    );

    await tester.enterText(
        find.byKey(const ValueKey('quick-open-input')), '>新建笔记');
    await _settle(tester);
    await tester.tap(find.text('笔记: 新建笔记'));
    await _settle(tester, rounds: 12);
    expect(h.workbench.activeTab!.resource!.scheme, 'notes');
    expect(h.workbench.activeTab!.resource!.basename, startsWith('未命名'));

    unawaitedRun(
        () => h.workbench.executeCommand('workbench.action.quickOpen'));
    await _settle(tester);
    await tester.enterText(
        find.byKey(const ValueKey('quick-open-input')), '会议');
    await _waitFor(tester, find.text('会议纪要'));
    await tester.tap(find.text('会议纪要'));
    await _settle(tester, rounds: 12);
    expect(h.workbench.activeTab!.resource.toString(), 'notes:/会议纪要.md');
  });

  testWidgets('资源管理器上下文菜单新建文件夹 / 删除（回收站）', (tester) async {
    await useSize(tester, const Size(1200, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(
        () => h.repo.createNode(isFolder: false, title: '待删', content: ''));
    await _pumpPage(tester, h);
    await tester.tap(find.text('笔记').first);
    await _waitFor(tester, find.text('待删.md'));

    final ui = _ScriptedUi();
    h.workbench.ui = ui;

    ui.promptResult = '资料';
    await tester.tap(find.byTooltip('新建文件夹'));
    await _waitFor(tester, find.text('资料'));
    expect(find.text('资料'), findsOneWidget);

    await tester.longPress(find.text('待删.md'));
    await _waitFor(tester, find.text('重命名'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('新建文件'), findsNothing);
    expect(find.text('重命名'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await _waitFor(tester, find.text('待删.md').hitTestable(), maxRounds: 1);
    for (var i = 0; i < 100 && find.text('待删.md').evaluate().isNotEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ui.confirmMessages.single, contains('回收站'));
    expect(find.text('待删.md'), findsNothing);
    final trashed = await tester.runAsync(() => h.repo.listTrash());
    expect(trashed, hasLength(1));
  });

  testWidgets('停用笔记插件：根节点变灰、笔记标签关闭、命令从面板消失；再启用恢复', (tester) async {
    await useSize(tester, const Size(1200, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(
        () => h.repo.createNode(isFolder: false, title: 'a', content: 'x'));
    await _pumpPage(tester, h);
    await tester.tap(find.text('笔记').first);
    await _waitFor(tester, find.text('a.md'));
    await tester.tap(find.text('a.md'));
    await _waitFor(tester, find.widgetWithText(TextField, 'x'));
    expect(h.workbench.tabs.where((t) => t.resource != null), hasLength(1));
    expect(h.workbench.paletteCommands().map((c) => c.command),
        contains('notes.newNote'));

    h.workbench.workspaceFolderSource = () async =>
        const [WorkspaceFolder(scheme: 'notes', name: '笔记', state: 'disabled')];
    await tester.runAsync(() => h.syncPlugins(notes: false));
    await tester.runAsync(h.workbench.refreshWorkspace);
    await _settle(tester);

    expect(h.workbench.tabs.where((t) => t.resource != null), isEmpty);
    expect(h.workbench.paletteCommands().map((c) => c.command),
        isNot(contains('notes.newNote')));
    expect(find.text('已停用'), findsOneWidget);
    expect(h.workbench.fileSystems.providerOf('notes'), isNull);

    h.workbench.workspaceFolderSource =
        () async => const [WorkspaceFolder(scheme: 'notes', name: '笔记')];
    await tester.runAsync(() => h.syncPlugins());
    await tester.runAsync(h.workbench.refreshWorkspace);
    await _settle(tester);
    expect(find.text('已停用'), findsNothing);
    await tester.tap(find.text('笔记').first);
    await _waitFor(tester, find.text('a.md'));
    expect(find.text('a.md'), findsOneWidget);
  });

  testWidgets('窄屏：抽屉里的资源管理器，打开文件后自动收起；顶栏标题跟随标签', (tester) async {
    await useSize(tester, const Size(400, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(
        () => h.repo.createNode(isFolder: false, title: '清单', content: '牛奶'));
    await _pumpPage(tester, h);
    expect(find.byKey(const ValueKey('activity-explorer')), findsNothing);

    await tester.tap(find.byTooltip('资源管理器').first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('activity-explorer')), findsOneWidget);
    await tester.tap(find.text('笔记').first);
    await _waitFor(tester, find.text('清单.md'));
    await tester.tap(find.text('清单.md'));
    await _waitFor(tester, find.widgetWithText(TextField, '牛奶'));

    expect(find.byKey(const ValueKey('activity-explorer')), findsNothing);
    expect(find.widgetWithText(TextField, '牛奶'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('清单')),
        findsWidgets);
  });

  testWidgets('只读资源：通用文本编辑器显示内容与只读标记', (tester) async {
    await useSize(tester, const Size(1200, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    h.workbench.fileSystems.register(
      MemoryFileSystemProvider('ro.demo',
          readOnly: true, files: {'/main.dart': 'void main() {}'}),
    );
    await _pumpPage(tester, h);
    await tester.runAsync(() =>
        h.workbench.openResource(ResourceUri.parse('ro.demo:/main.dart')));
    await _settle(tester);
    expect(find.text('void main() {}'), findsOneWidget);
    expect(find.text('只读'), findsWidgets);
    expect(h.workbench.activeTab!.viewType, 'workbench.text');
  });

  testWidgets('资源不存在：编辑器给出明确提示而不是崩溃', (tester) async {
    await useSize(tester, const Size(1200, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    h.workbench.fileSystems.register(MemoryFileSystemProvider('mem'));
    await _pumpPage(tester, h);
    await tester.runAsync(
        () => h.workbench.openResource(ResourceUri.parse('mem:/gone.txt')));
    await _settle(tester);
    expect(find.textContaining('文件已不存在'), findsOneWidget);
  });
}

void unawaitedRun(Future<Object?> Function() action) {
  action().catchError((Object _) => null);
}

class _ScriptedUi extends HeadlessWorkbenchUi {
  final List<String> confirmMessages = [];

  @override
  Future<bool> confirm({
    required String title,
    required String message,
    String confirmLabel = '确定',
    bool destructive = false,
  }) async {
    confirmMessages.add(message);
    return true;
  }
}
