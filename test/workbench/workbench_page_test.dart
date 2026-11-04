import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:notepad/main.dart';
import 'package:notepad/plugins/plugin_manager.dart';
import 'package:notepad/theme/theme_controller.dart';
import 'package:notepad/workbench/bootstrap.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/notes_repository.dart';
import 'package:notepad/data/vault/vault_notes_repository.dart';
import 'package:notepad/plugins/builtin_plugins.dart';
import 'package:notepad/plugins/plugin_model.dart';
import 'package:notepad/services/settings_service.dart';
import 'package:notepad/state/note_provider.dart';
import 'package:notepad/ui/home/home_page.dart';
import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/extensions/core_extension.dart';
import 'package:notepad/workbench/extensions/notes_extension.dart';
import 'package:notepad/workbench/services/editor_registry.dart';
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

Future<_Harness> _createHarness(WidgetTester tester,
    {Map<String, Object?>? session}) async {
  return (await tester.runAsync(() async {
    final tempDir = await Directory.systemTemp.createTemp('notepad_wb_ui_');
    final repo = VaultNotesRepository.atRoot(tempDir.path);
    await repo.init();
    final workbench =
        Workbench(sessionStore: MemorySessionStore()..data = session);
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

  testWidgets('设置里切换插件系统：根界面在笔记首页与工作台之间切换且无断言', (tester) async {
    await useSize(tester, const Size(400, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(() async {
      await h.repo.createNode(isFolder: true, title: '工作');
      await h.repo.createNode(isFolder: false, title: '清单', content: '牛奶');
      await h.repo.createNode(isFolder: false, title: '随笔', content: 'hi');
    });
    final settings = (await tester.runAsync(() => SettingsService.instance))!;
    addTearDown(() => settings.setEnablePluginSystem(false));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => NoteProvider(repository: h.repo)),
          ChangeNotifierProvider<Workbench>.value(value: h.workbench),
          Provider<QuickOpenService>.value(value: h.quickOpen),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: settings.pluginSystemEnabled,
            builder: (context, ide, _) =>
                ide ? const WorkbenchPage() : const HomePage(),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await _settle(tester);
    await tester.tap(find.text('设置').last);
    await _waitFor(tester, find.text('显示与主题'));
    await tester.scrollUntilVisible(find.text('启用插件系统'), 300,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('启用插件系统'), findsOneWidget);

    await tester.tap(find.text('启用插件系统'));
    await tester.pump();
    await tester.pageBack();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await _settle(tester);
    expect(find.byType(WorkbenchPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('资源管理器').first);
    await _settle(tester);
    await tester.tap(find.byTooltip('设置').first);
    await _waitFor(tester, find.text('显示与主题'));
    await tester.scrollUntilVisible(find.text('启用插件系统'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('启用插件系统'));
    await tester.pump();
    await tester.pageBack();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await _settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('会话恢复：重启后笔记标签在插件尚未激活时恢复，不抛断言', (tester) async {
    await useSize(tester, const Size(400, 800));
    final h = await _createHarness(tester, session: {
      'tabs': [
        {'uri': 'notes:/清单.md', 'viewType': 'notes.markdown'},
        {'viewType': kWelcomeViewType},
      ],
      'active': 0,
      'recent': ['notes:/清单.md'],
    });
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(
        () => h.repo.createNode(isFolder: false, title: '清单', content: '牛奶'));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => NoteProvider(repository: h.repo)),
          ChangeNotifierProvider<Workbench>.value(value: h.workbench),
          Provider<QuickOpenService>.value(value: h.quickOpen),
        ],
        child: const MaterialApp(home: WorkbenchPage()),
      ),
    );
    await _waitFor(tester, find.widgetWithText(TextField, '牛奶'));
    expect(find.widgetWithText(TextField, '牛奶'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏连续操作：开关标签 / 切换 / 停用启用插件 / 抽屉，全程无异常', (tester) async {
    await useSize(tester, const Size(400, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(() async {
      await h.repo.createNode(isFolder: false, title: 'a', content: 'x');
      await h.repo.createNode(isFolder: false, title: 'b', content: 'y');
    });
    await _pumpPage(tester, h);
    final a = ResourceUri.parse('notes:/a.md');
    final b = ResourceUri.parse('notes:/b.md');

    Future<void> step(Future<Object?> Function() action) async {
      await tester.runAsync(() async {
        try {
          await action();
        } catch (_) {}
      });
      await _settle(tester, rounds: 4);
      expect(tester.takeException(), isNull);
    }

    await step(() => h.workbench.openResource(a));
    await _waitFor(tester, find.widgetWithText(TextField, 'x'));
    await tester.tap(find.widgetWithText(TextField, 'x'));
    await tester.enterText(find.widgetWithText(TextField, 'x'), 'xx');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await step(() => h.workbench.openResource(b));
    await step(() async => h.workbench.activateTab(1));
    await tester.tap(find.byTooltip('资源管理器').first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    unawaitedRun(() => h.workbench.executeCommand('notes.preview'));
    await _waitFor(tester, find.byType(BackButton));
    await _settle(tester);
    await tester.pageBack();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    unawaitedRun(() => h.workbench.executeCommand('workbench.action.openWith'));
    await _settle(tester);
    await tester.tapAt(const Offset(200, 20));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await step(() async => h.workbench.closeTab(0));
    await step(() async => h.workbench.reopenClosedTab());

    h.workbench.workspaceFolderSource = () async =>
        const [WorkspaceFolder(scheme: 'notes', name: '笔记', state: 'disabled')];
    await step(() => h.syncPlugins(notes: false));
    await step(h.workbench.refreshWorkspace);
    h.workbench.workspaceFolderSource =
        () async => const [WorkspaceFolder(scheme: 'notes', name: '笔记')];
    await step(() => h.syncPlugins());
    await step(h.workbench.refreshWorkspace);
    await step(() => h.workbench.openResource(a));
    await _waitFor(tester, find.byType(TextField));
    await step(() async => h.workbench.closeAllTabs());
  });

  testWidgets('整应用（真实插件管理器 + 运行时）：插件中心里反复启停插件不抛异常', (tester) async {
    await useSize(tester, const Size(400, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await tester.runAsync(
        () => h.repo.createNode(isFolder: false, title: '清单', content: '牛奶'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => h.tempDir.path);
    final runtime = (await tester.runAsync(() async {
      await PluginManager.instance.init();
      PluginManager.instance
        ..registerBuiltin(builtinNotesPlugin())
        ..registerBuiltin(builtinFileBrowserPlugin());
      return createWorkbenchRuntime(
        repository: h.repo,
        plugins: PluginManager.instance,
        sessionStore: MemorySessionStore(),
      );
    }))!;
    addTearDown(() => tester.runAsync(() async => runtime.dispose()));

    await tester.pumpWidget(
      NotePadApp(
        themeController: ThemeController(),
        repository: h.repo,
        workbench: runtime,
        pluginSystemEnabled: ValueNotifier<bool>(true),
      ),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('资源管理器').first);
    await _settle(tester);
    await tester.tap(find.text('笔记').first);
    await _waitFor(tester, find.text('清单.md'));
    await tester.tap(find.text('清单.md'));
    await _waitFor(tester, find.widgetWithText(TextField, '牛奶'));
    expect(tester.takeException(), isNull);

    unawaitedRun(() =>
        runtime.workbench.executeCommand('workbench.action.openPluginCenter'));
    await _waitFor(tester, find.byType(Switch));
    await _settle(tester);

    for (var round = 0; round < 2; round++) {
      for (final index in [0, 1]) {
        await tester.tap(find.byType(Switch).at(index));
        await _settle(tester, rounds: 10);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(Switch).at(index));
        await _settle(tester, rounds: 10);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pageBack();
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入对话框关闭动画期间不再使用已释放的控制器', (tester) async {
    await useSize(tester, const Size(400, 800));
    final h = await _createHarness(tester);
    addTearDown(() => tester.runAsync(h.dispose));
    await _pumpPage(tester, h);

    final result = h.workbench.ui.prompt(title: '新建文件', initialValue: 'a.md');
    await _settle(tester);
    expect(find.byKey(const ValueKey('prompt-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('prompt-input')), 'b.md');
    await tester.tap(find.text('确定'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(await result, 'b.md');
    expect(tester.takeException(), isNull);
  });

  for (final (width, seed) in [
    (400.0, 1),
    (400.0, 2),
    (400.0, 3),
    (1200.0, 1),
    (1200.0, 2),
    (1200.0, 3),
  ]) {
    testWidgets('随机点击压力 width=$width seed=$seed：无未捕获异常', (tester) async {
      await useSize(tester, Size(width, 800));
      final h = await _createHarness(tester);
      addTearDown(() => tester.runAsync(h.dispose));
      await tester.runAsync(() async {
        await h.repo.createNode(isFolder: false, title: 'a', content: 'x');
        await h.repo.createNode(isFolder: false, title: 'b', content: 'y');
        await h.repo.createNode(isFolder: true, title: 'dir');
      });
      await _pumpPage(tester, h);
      final random = math.Random(seed);
      final log = <String>[];
      FlutterErrorDetails? captured;
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        captured ??= details;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      for (var i = 0; i < 250; i++) {
        final candidates = <Finder>[
          find.byType(IconButton),
          find.byType(ListTile),
          find.byType(TextButton),
          find.byType(OutlinedButton),
          find.byType(InkWell),
          find.byType(PopupMenuButton<String>),
        ];
        final finder = candidates[random.nextInt(candidates.length)];
        final count = finder.evaluate().length;
        final fields = find.byType(TextField);
        if (fields.evaluate().isNotEmpty && random.nextInt(3) == 0) {
          try {
            await tester.enterText(
                fields.at(random.nextInt(fields.evaluate().length)),
                'n${random.nextInt(99)}');
          } catch (_) {}
        } else if (count > 0) {
          final target = finder.at(random.nextInt(count));
          log.add('$i ${target.evaluate().first.widget.runtimeType}');
          try {
            await tester.tap(target, warnIfMissed: false);
          } catch (e) {
            log.add('  tap err: $e');
          }
        }
        if (random.nextInt(10) == 0) {
          try {
            final nav =
                tester.state<NavigatorState>(find.byType(Navigator).first);
            if (nav.canPop()) nav.pop();
          } catch (_) {}
        }
        try {
          final nav =
              tester.state<NavigatorState>(find.byType(Navigator).first);
          var pushedPage = false;
          nav.popUntil((route) {
            pushedPage =
                pushedPage || route is MaterialPageRoute && !route.isFirst;
            return route.isFirst || route is! MaterialPageRoute;
          });
        } catch (_) {}
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 120));
        final error = tester.takeException();
        if (error != null) {
          final recent = log.reversed.take(12).toList().reversed.join('\n');
          FlutterError.onError = previous;
          fail(
              'step $i: ${captured?.exception ?? error}\n${captured?.stack}\n$recent');
        }
      }
    });
  }
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
