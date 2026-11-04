import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/services/command_registry.dart';
import 'package:notepad/workbench/services/contribution_registry.dart';
import 'package:notepad/workbench/services/editor_registry.dart';
import 'package:notepad/workbench/services/extension_host.dart';
import 'package:notepad/workbench/services/file_system.dart';
import 'package:notepad/workbench/services/quick_open.dart';
import 'package:notepad/workbench/services/workbench.dart';

import 'fakes.dart';

class _RecordingExtension extends HostExtension {
  _RecordingExtension(this.log, {this.fail = false, this.scheme});

  final List<String> log;
  final bool fail;
  final String? scheme;

  @override
  Future<void> activate(ExtensionContext context) async {
    log.add('activate:${context.pluginId}');
    context.registerCommand('demo.hello', (ctx) => 'hello ${ctx.args.join(',')}');
    context.registerCommand('demo.hidden', (ctx) => null);
    context.setContext('demoActive', true);
    if (scheme != null) {
      context.registerFileSystemProvider(
        MemoryFileSystemProvider(scheme!, files: {'/a.txt': 'A'}),
      );
    }
    if (fail) throw StateError('activate failed');
  }

  @override
  void deactivate() => log.add('deactivate');
}

Map<String, Object?> _contributes() => {
      'commands': [
        {'command': 'demo.hello', 'title': 'Hello', 'category': 'Demo'},
        {
          'command': 'demo.macro',
          'title': 'Macro',
          'run': [
            {'command': 'demo.hello', 'args': ['x', 'y']},
          ],
        },
        {'command': 'demo.ghost', 'title': 'Ghost'},
        {'command': 'demo.hidden', 'title': 'Hidden', 'when': 'demoActive'},
        {
          'command': 'demo.loop',
          'title': 'Loop',
          'run': [
            {'command': 'demo.loop'},
          ],
        },
      ],
      'menus': {
        'explorer/context': [
          {
            'command': 'demo.hello',
            'when': 'explorerResourceFamily == demo',
            'group': '2_b',
          },
          {'command': 'demo.macro', 'group': '1_a'},
          {'command': 'not.declared', 'group': '0_x'},
        ],
        'commandPalette': [
          {'command': 'demo.ghost', 'when': 'false'},
        ],
      },
      'editors': [
        {
          'viewType': 'demo.editor',
          'displayName': 'Demo',
          'priority': 'default',
          'selector': [
            {'scheme': 'demo', 'filenamePattern': '*.{txt,log}'},
          ],
        },
        {
          'viewType': 'demo.alt',
          'displayName': 'Alt',
          'selector': [
            {'filenamePattern': '*.txt'},
          ],
        },
      ],
      'viewsContainers': {
        'activitybar': [
          {'id': 'demo', 'title': 'Demo', 'icon': 'search'},
        ],
      },
      'views': {
        'demo': [
          {'id': 'demo.view', 'name': 'Demo View'},
        ],
      },
      'statusBar': [
        {'id': 'demo.status', 'text': 'demo', 'command': 'demo.hello'},
      ],
    };

void main() {
  group('PluginContributions.parse', () {
    test('解析各贡献点并跳过缺字段的坏条目', () {
      final parsed = PluginContributions.parse('p', {
        ..._contributes(),
        'commands': [
          ...(_contributes()['commands']! as List),
          {'command': '', 'title': 'bad'},
          {'title': 'no id'},
          'not a map',
        ],
      });
      expect(parsed.commands.map((c) => c.command),
          ['demo.hello', 'demo.macro', 'demo.ghost', 'demo.hidden', 'demo.loop']);
      expect(parsed.commands.first.label, 'Demo: Hello');
      expect(parsed.commands[1].run.single.args, ['x', 'y']);
      expect(parsed.menus, hasLength(4));
      expect(parsed.viewContainers.single.id, 'demo');
      expect(parsed.views.single.container, 'demo');
      expect(parsed.editors.first.priority, EditorPriority.defaultPriority);
      expect(parsed.editors.last.priority, EditorPriority.option);
      expect(parsed.statusBar.single.alignment, 'left');
    });

    test('null / 空输入得到空贡献', () {
      expect(PluginContributions.parse('p', null).isEmpty, isTrue);
      expect(PluginContributions.parse('p', const {}).isEmpty, isTrue);
    });
  });

  group('globMatches', () {
    test('通配 * ? {a,b}，大小写不敏感，整名匹配', () {
      expect(globMatches('*.md', 'Note.MD'), isTrue);
      expect(globMatches('*.md', 'note.md.bak'), isFalse);
      expect(globMatches('?.txt', 'a.txt'), isTrue);
      expect(globMatches('?.txt', 'ab.txt'), isFalse);
      expect(globMatches('*.{md,txt}', 'a.txt'), isTrue);
      expect(globMatches('*.{md,txt}', 'a.dart'), isFalse);
      expect(globMatches('a.b', 'axb'), isFalse);
    });
  });

  group('ContributionRegistry', () {
    test('菜单按 group / order 排序，丢弃未声明命令的条目', () {
      final registry = ContributionRegistry()
        ..setPlugin('p', PluginContributions.parse('p', _contributes()));
      final items = registry.menu(MenuIds.explorerContext);
      expect(items.map((m) => m.command), ['demo.macro', 'demo.hello']);
    });

    test('移除插件后贡献消失并通知', () {
      final registry = ContributionRegistry();
      var notified = 0;
      registry.addListener(() => notified++);
      registry.setPlugin('p', PluginContributions.parse('p', _contributes()));
      expect(registry.command('demo.hello'), isNotNull);
      registry.removePlugin('p');
      registry.removePlugin('p');
      expect(registry.command('demo.hello'), isNull);
      expect(notified, 2);
    });
  });

  group('EditorRegistry 解析', () {
    late ContributionRegistry contributions;
    late EditorRegistry editors;

    setUp(() {
      contributions = ContributionRegistry()
        ..setPlugin('p', PluginContributions.parse('p', _contributes()));
      editors = EditorRegistry(contributions);
    });

    test('default 优先级胜出；option 只出现在候选里', () {
      final uri = ResourceUri.parse('demo:/a.txt');
      expect(editors.resolve(uri), 'demo.editor');
      expect(editors.candidates(uri).map((e) => e.viewType),
          ['demo.editor', 'demo.alt']);
    });

    test('只有 option 匹配时回退到通用文本编辑器', () {
      final uri = ResourceUri.parse('other:/a.txt');
      expect(editors.candidates(uri).single.viewType, 'demo.alt');
      expect(editors.resolve(uri), kTextEditorViewType);
      expect(editors.resolve(ResourceUri.parse('other:/a.dart')),
          kTextEditorViewType);
    });

    test('builtin 候选优先于通用文本编辑器', () {
      contributions.setPlugin(
        'core',
        PluginContributions.parse('core', {
          'editors': [
            {
              'viewType': 'core.fallback',
              'priority': 'builtin',
              'selector': [{}],
            },
          ],
        }),
      );
      expect(editors.resolve(ResourceUri.parse('other:/a.dart')),
          'core.fallback');
    });

    test('provider 重复注册报错，释放后可重新注册', () {
      Widget builder(BuildContext c, EditorInput i) => const SizedBox();
      final d = editors.register('v', builder);
      expect(() => editors.register('v', builder), throwsStateError);
      d.dispose();
      expect(editors.hasProvider('v'), isFalse);
      editors.register('v', builder);
      expect(editors.hasProvider('v'), isTrue);
    });
  });

  group('FileSystemRegistry', () {
    test('按 scheme 分发；重复注册报错；释放后不可用', () async {
      final registry = FileSystemRegistry();
      final provider = MemoryFileSystemProvider('mem', files: {'/a.txt': 'A'});
      final registration = registry.register(provider);
      expect(() => registry.register(MemoryFileSystemProvider('mem')),
          throwsStateError);

      expect(await registry.readText(ResourceUri.parse('mem:/a.txt')), 'A');
      expect(await registry.isReadOnly(ResourceUri('mem')), isFalse);

      registration.dispose();
      await expectLater(
        registry.readText(ResourceUri.parse('mem:/a.txt')),
        throwsA(isA<FileSystemError>()
            .having((e) => e.code, 'code', 'E-NO-PROVIDER')),
      );
    });

    test('未注册时通过激活器懒加载 provider', () async {
      final registry = FileSystemRegistry();
      var activations = 0;
      registry.activator = (scheme) async {
        activations++;
        registry.register(MemoryFileSystemProvider(scheme, files: {'/x': '1'}));
      };
      expect(await registry.readText(ResourceUri.parse('lazy:/x')), '1');
      expect(await registry.readText(ResourceUri.parse('lazy:/x')), '1');
      expect(activations, 1);
    });

    test('只读 provider 的写操作抛 E-READONLY（默认实现）', () async {
      final registry = FileSystemRegistry();
      registry.register(_ReadOnlyProvider());
      await expectLater(
        registry.writeText(ResourceUri.parse('ro:/a'), 'x'),
        throwsA(isA<FileSystemError>()
            .having((e) => e.code, 'code', 'E-READONLY')),
      );
      await expectLater(
        registry.delete(ResourceUri.parse('ro:/a')),
        throwsA(isA<FileSystemError>()),
      );
    });

    test('provider 变更事件被转发', () async {
      final registry = FileSystemRegistry();
      final provider = MemoryFileSystemProvider('mem');
      registry.register(provider);
      final events = <ResourceUri>[];
      final sub = registry.onDidChange.listen(events.add);
      await provider.createFile(ResourceUri('mem'), 'n.txt');
      await Future<void>.delayed(Duration.zero);
      expect(events.single, ResourceUri('mem'));
      await sub.cancel();
    });
  });

  group('ExtensionHost 与命令', () {
    late Workbench workbench;
    late ExtensionHost host;
    late List<String> log;

    PluginInfo plugin({
      bool enabled = true,
      List<String> events = const ['onCommand:demo.*'],
      Map<String, Object?>? contributes,
      String capability = 'demo.cap',
    }) =>
        PluginInfo(
          id: 'demo',
          capability: capability,
          enabled: enabled,
          contributes: contributes ?? _contributes(),
          activationEvents: events,
        );

    setUp(() {
      log = [];
      workbench = Workbench();
      host = ExtensionHost(workbench)
        ..registerFactory('demo.cap', () => _RecordingExtension(log));
    });

    tearDown(() {
      host.dispose();
      workbench.dispose();
    });

    test('同步后只加载贡献，不激活；执行命令时按 onCommand 懒激活', () async {
      await host.sync([plugin()]);
      expect(log, isEmpty);
      expect(workbench.contributions.command('demo.hello'), isNotNull);
      expect(host.isActive('demo'), isFalse);

      final result = await workbench.executeCommand('demo.hello', ['a', 'b']);
      expect(result, 'hello a,b');
      expect(log, ['activate:demo']);
      expect(host.isActive('demo'), isTrue);

      await workbench.executeCommand('demo.hello');
      expect(log, ['activate:demo']);
    });

    test('onStartup / * 在同步时立即激活', () async {
      await host.sync([plugin(events: const ['onStartup'])]);
      expect(log, ['activate:demo']);
      await host.sync([plugin(events: const ['onStartup'])]);
      expect(log, ['activate:demo']);
    });

    test('未声明事件的插件默认启动时激活', () async {
      await host.sync([plugin(events: const [])]);
      expect(log, ['activate:demo']);
    });

    test('声明式宏：无处理函数时按 run 顺序执行', () async {
      await host.sync([plugin()]);
      expect(await workbench.executeCommand('demo.macro'), 'hello x,y');
    });

    test('宏循环被深度限制拦截', () async {
      await host.sync([plugin()]);
      await expectLater(
        workbench.executeCommand('demo.loop'),
        throwsA(isA<StateError>()),
      );
    });

    test('未知命令与已声明但无实现的命令给出明确错误', () async {
      await host.sync([plugin()]);
      await expectLater(
        workbench.executeCommand('nope'),
        throwsA(isA<CommandNotFoundError>().having((e) => e.declared, 'declared', false)),
      );
      await expectLater(
        workbench.executeCommand('demo.ghost'),
        throwsA(isA<CommandNotFoundError>().having((e) => e.declared, 'declared', true)),
      );
    });

    test('停用：命令 / 贡献 / 上下文 / 文件系统全部释放，并关闭其标签', () async {
      host.registerFactory(
        'demo.cap',
        () => _RecordingExtension(log, scheme: 'demo'),
      );
      await host.sync([plugin()]);
      await workbench.executeCommand('demo.hello');
      expect(workbench.contextKeys.get('demoActive'), isTrue);
      await workbench.openResource(ResourceUri.parse('demo:/a.txt'));
      expect(workbench.tabs, hasLength(1));

      await host.sync([plugin(enabled: false)]);
      expect(log, ['activate:demo', 'deactivate']);
      expect(workbench.commands.hasHandler('demo.hello'), isFalse);
      expect(workbench.contributions.command('demo.hello'), isNull);
      expect(workbench.contextKeys.get('demoActive'), isNull);
      expect(workbench.fileSystems.providerOf('demo'), isNull);
      expect(workbench.tabs, isEmpty);
      await expectLater(
        workbench.executeCommand('demo.hello'),
        throwsA(isA<CommandNotFoundError>()),
      );
    });

    test('停用后重新启用会重新激活', () async {
      await host.sync([plugin()]);
      await workbench.executeCommand('demo.hello');
      await host.sync([plugin(enabled: false)]);
      await host.sync([plugin()]);
      await workbench.executeCommand('demo.hello');
      expect(log.where((l) => l.startsWith('activate')), hasLength(2));
    });

    test('manifest 变化（签名不同）会重建插件', () async {
      await host.sync([plugin()]);
      await workbench.executeCommand('demo.hello');
      await host.sync([
        plugin(contributes: {
          'commands': [
            {'command': 'demo.hello', 'title': 'Renamed'},
          ],
        }),
      ]);
      expect(log, ['activate:demo', 'deactivate']);
      expect(workbench.contributions.command('demo.hello')!.title, 'Renamed');
      expect(workbench.contributions.command('demo.macro'), isNull);
    });

    test('激活失败：记录错误、释放已注册内容，且不再重试', () async {
      host.registerFactory(
        'demo.cap',
        () => _RecordingExtension(log, fail: true),
      );
      await host.sync([plugin()]);
      await expectLater(
        workbench.executeCommand('demo.hello'),
        throwsA(isA<CommandNotFoundError>()),
      );
      expect(host.errorOf('demo'), contains('activate failed'));
      expect(workbench.commands.hasHandler('demo.hello'), isFalse);
      expect(workbench.contextKeys.get('demoActive'), isNull);
      await expectLater(
        workbench.executeCommand('demo.hello'),
        throwsA(isA<CommandNotFoundError>()),
      );
      expect(log.where((l) => l.startsWith('activate')), hasLength(1));
    });

    test('并发触发同一激活事件只激活一次', () async {
      await host.sync([plugin()]);
      await Future.wait([
        workbench.executeCommand('demo.hello'),
        workbench.executeCommand('demo.hello'),
        host.activateByEvent('onCommand:demo.hello'),
      ]);
      expect(log, ['activate:demo']);
    });

    test('纯声明式插件（无工厂）立即视为已激活，宏可用', () async {
      await host.sync([
        PluginInfo(
          id: 'macro-only',
          capability: 'no.factory',
          enabled: true,
          contributes: {
            'commands': [
              {
                'command': 'macro.run',
                'title': 'Run',
                'run': [
                  {'command': 'workbench.test'},
                ],
              },
            ],
          },
        ),
      ]);
      workbench.commands.register('workbench.test', (_) => 42);
      expect(await workbench.executeCommand('macro.run'), 42);
      expect(host.isActive('macro-only'), isTrue);
    });

    test('onResource 通配：打开资源时激活提供文件系统的插件', () async {
      host.registerFactory(
        'demo.cap',
        () => _RecordingExtension(log, scheme: 'demo.p1'),
      );
      await host.sync([plugin(events: const ['onResource:demo.*'])]);
      expect(log, isEmpty);
      final text = await workbench.fileSystems
          .readText(ResourceUri.parse('demo.p1:/a.txt'));
      expect(text, 'A');
      expect(log, ['activate:demo']);
    });

    test('matchesEvent 规则', () {
      expect(ExtensionHost.matchesEvent('onStartup', 'onStartup'), isTrue);
      expect(ExtensionHost.matchesEvent('*', 'onStartup'), isTrue);
      expect(ExtensionHost.matchesEvent('*', 'onCommand:x'), isFalse);
      expect(ExtensionHost.matchesEvent('onCommand:a.*', 'onCommand:a.b'), isTrue);
      expect(ExtensionHost.matchesEvent('onCommand:a.*', 'onCommand:b.a'), isFalse);
      expect(ExtensionHost.matchesEvent('onResource:files', 'onResource:files.p'),
          isFalse);
    });

    test('paletteCommands：声明 + when + 可执行（含可懒激活）', () async {
      await host.sync([plugin()]);
      var labels = workbench.paletteCommands().map((c) => c.command).toList();
      // hello 可懒激活；macro 有 run；ghost 无实现且命令面板菜单 when=false；
      // hidden 的 when 依赖 demoActive（未激活）。
      expect(labels, containsAll(['demo.hello', 'demo.macro']));
      expect(labels, isNot(contains('demo.ghost')));
      expect(labels, isNot(contains('demo.hidden')));

      await workbench.executeCommand('demo.hello');
      labels = workbench.paletteCommands().map((c) => c.command).toList();
      expect(labels, contains('demo.hidden'));
    });

    test('visibleMenu 按 when 过滤并支持覆盖值', () async {
      await host.sync([plugin()]);
      List<String> ids([Map<String, Object?>? o]) => workbench
          .visibleMenu(MenuIds.explorerContext, overrides: o)
          .map((m) => m.command)
          .toList();
      expect(ids(), ['demo.macro']);
      expect(ids({'explorerResourceFamily': 'demo'}),
          ['demo.macro', 'demo.hello']);
    });
  });

  group('Workbench 标签与会话', () {
    late MemorySessionStore store;
    late Workbench workbench;

    setUp(() {
      store = MemorySessionStore();
      workbench = Workbench(sessionStore: store);
      workbench.fileSystems.register(MemoryFileSystemProvider(
        'mem',
        files: {'/a.md': 'A', '/b.txt': 'B', '/dir/c.txt': 'C'},
      ));
    });

    tearDown(() => workbench.dispose());

    test('打开同一资源复用标签；上下文键随活动标签更新', () async {
      final a = await workbench.openResource(ResourceUri.parse('mem:/a.md'));
      final again = await workbench.openResource(ResourceUri.parse('mem:/a.md'));
      expect(identical(a, again), isTrue);
      expect(workbench.tabs, hasLength(1));

      await workbench.openResource(ResourceUri.parse('mem:/b.txt'));
      expect(workbench.activeIndex, 1);
      expect(workbench.contextKeys.get('resourceFilename'), 'b.txt');
      expect(workbench.contextKeys.get('resourceExtname'), '.txt');
      expect(workbench.contextKeys.get('resourceScheme'), 'mem');
      expect(workbench.contextKeys.get('resourceReadOnly'), isFalse);
      expect(workbench.contextKeys.get('editorViewType'), kTextEditorViewType);
      expect(workbench.contextKeys.get('openEditorCount'), 2);

      workbench.activateTab(0);
      expect(workbench.contextKeys.get('resourceFilename'), 'a.md');
    });

    test('同一资源用不同编辑器打开是不同标签', () async {
      final uri = ResourceUri.parse('mem:/a.md');
      await workbench.openResource(uri);
      await workbench.openResource(uri, viewType: 'other.editor');
      expect(workbench.tabs, hasLength(2));
    });

    test('关闭标签后活动索引正确回落', () async {
      for (final name in ['a.md', 'b.txt', 'dir/c.txt']) {
        await workbench.openResource(ResourceUri.parse('mem:/$name'));
      }
      workbench.activateTab(1);
      workbench.closeTab(0);
      expect(workbench.activeIndex, 0);
      expect(workbench.activeTab!.resource!.basename, 'b.txt');

      workbench.closeTab(0);
      expect(workbench.activeTab!.resource!.basename, 'c.txt');
      workbench.closeActiveTab();
      expect(workbench.tabs, isEmpty);
      expect(workbench.activeIndex, -1);
      expect(workbench.contextKeys.get('activeEditor'), isFalse);
    });

    test('next / previous 循环切换；closeOthers / closeAll', () async {
      for (final name in ['a.md', 'b.txt', 'dir/c.txt']) {
        await workbench.openResource(ResourceUri.parse('mem:/$name'));
      }
      workbench.nextTab();
      expect(workbench.activeIndex, 0);
      workbench.previousTab();
      expect(workbench.activeIndex, 2);
      workbench.closeOtherTabs(1);
      expect(workbench.tabs.map((t) => t.resource!.basename), ['b.txt']);
      workbench.closeAllTabs();
      expect(workbench.tabs, isEmpty);
    });

    test('重新打开已关闭的标签；最近文件去重并按时间倒序', () async {
      final a = ResourceUri.parse('mem:/a.md');
      final b = ResourceUri.parse('mem:/b.txt');
      await workbench.openResource(a);
      await workbench.openResource(b);
      await workbench.openResource(a);
      expect(workbench.recentResources, [a, b]);

      workbench.closeTab(0);
      final reopened = await workbench.reopenClosedTab();
      expect(reopened!.resource, a);
      expect(await Workbench().reopenClosedTab(), isNull);
    });

    test('closeTabsUnder 关闭目录下的标签', () async {
      await workbench.openResource(ResourceUri.parse('mem:/dir/c.txt'));
      await workbench.openResource(ResourceUri.parse('mem:/a.md'));
      workbench.closeTabsUnder(ResourceUri.parse('mem:/dir'));
      expect(workbench.tabs.map((t) => t.resource!.basename), ['a.md']);
    });

    test('无资源编辑器（欢迎页）只开一个', () {
      final first = workbench.openEditor(kWelcomeViewType, title: '欢迎');
      final second = workbench.openEditor(kWelcomeViewType, title: '欢迎');
      expect(identical(first, second), isTrue);
      expect(workbench.contextKeys.get('resourceScheme'), isNull);
    });

    test('会话保存与恢复：标签 / 活动项 / 最近 / 侧栏', () async {
      await workbench.openResource(ResourceUri.parse('mem:/a.md'));
      await workbench.openResource(ResourceUri.parse('mem:/b.txt'));
      workbench.openEditor(kWelcomeViewType, title: '欢迎');
      workbench.activateTab(1);
      workbench.selectContainer('search');
      await Future<void>.delayed(Duration.zero);

      final restored = Workbench(sessionStore: store);
      addTearDown(restored.dispose);
      await restored.restoreSession();
      expect(restored.tabs.map((t) => t.viewType),
          [kTextEditorViewType, kTextEditorViewType, kWelcomeViewType]);
      expect(restored.tabs[2].resource, isNull);
      expect(restored.activeIndex, 1);
      expect(restored.activeContainer, 'search');
      expect(restored.recentResources.map((u) => u.path), ['/b.txt', '/a.md']);
      expect(restored.contextKeys.get('resourceFilename'), 'b.txt');
    });

    test('会话数据损坏时忽略坏条目', () async {
      store.data = {
        'tabs': [
          {'uri': 'bad uri without scheme', 'viewType': 'x'},
          {'viewType': 5},
          'junk',
          {'uri': 'mem:/a.md', 'viewType': kTextEditorViewType},
        ],
        'active': 99,
        'recent': ['::', 3, 'mem:/a.md'],
      };
      await workbench.restoreSession();
      expect(workbench.tabs, hasLength(1));
      expect(workbench.activeIndex, 0);
      expect(workbench.recentResources, [ResourceUri.parse('mem:/a.md')]);
    });

    test('侧栏：点击当前容器收起 / 展开；切换容器强制展开', () {
      expect(workbench.sidebarVisible, isTrue);
      workbench.selectContainer('explorer');
      expect(workbench.sidebarVisible, isFalse);
      expect(workbench.contextKeys.get('sidebarVisible'), isFalse);
      workbench.selectContainer('search');
      expect(workbench.sidebarVisible, isTrue);
      expect(workbench.activeContainer, 'search');
    });

    test('资源管理器选中项写入上下文', () {
      workbench.setExplorerSelection(
        ResourceUri.parse('mem:/dir'),
        isFolder: true,
      );
      expect(workbench.contextKeys.get('explorerResourceScheme'), 'mem');
      expect(workbench.contextKeys.get('explorerResourceIsFolder'), isTrue);
      expect(workbench.contextKeys.get('explorerResourceIsRoot'), isFalse);
      expect(workbench.contextKeys.get('explorerResourceReadOnly'), isFalse);
      workbench.setExplorerSelection(null);
      expect(workbench.contextKeys.get('explorerResourceIsFolder'), isFalse);
    });

    test('工作区文件夹：只统计 active 的', () async {
      workbench.workspaceFolderSource = () async => const [
            WorkspaceFolder(scheme: 'notes', name: '笔记'),
            WorkspaceFolder(scheme: 'files.p', name: 'p', state: 'disabled'),
          ];
      await workbench.refreshWorkspace();
      expect(workbench.workspaceFolders, hasLength(2));
      expect(workbench.activeFolders.single.scheme, 'notes');
      expect(workbench.contextKeys.get('workspaceFolderCount'), 1);
    });
  });

  group('QuickOpenService', () {
    late Workbench workbench;
    late QuickOpenService quickOpen;

    setUp(() async {
      workbench = Workbench();
      workbench.fileSystems.register(MemoryFileSystemProvider(
        'mem',
        files: {
          '/readme.md': '',
          '/src/main.dart': '',
          '/src/util/strings.dart': '',
          '/docs/guide.md': '',
        },
      ));
      workbench.workspaceFolderSource = () async =>
          const [WorkspaceFolder(scheme: 'mem', name: 'mem')];
      await workbench.refreshWorkspace();
      quickOpen = QuickOpenService(workbench);
    });

    tearDown(() {
      quickOpen.dispose();
      workbench.dispose();
    });

    test('文件名模糊匹配，文件名命中优先', () async {
      final matches = await quickOpen.findFiles('main');
      expect(matches.first.uri.path, '/src/main.dart');
      final dart = await quickOpen.findFiles('dart');
      expect(dart.map((m) => m.uri.basename), containsAll(['main.dart', 'strings.dart']));
      expect(await quickOpen.findFiles('zzzz'), isEmpty);
    });

    test('空查询返回最近打开的文件', () async {
      expect(await quickOpen.findFiles(''), isEmpty);
      await workbench.openResource(ResourceUri.parse('mem:/readme.md'));
      final recent = await quickOpen.findFiles('');
      expect(recent.single.uri.path, '/readme.md');
    });

    test('文件系统变化后索引失效', () async {
      expect(await quickOpen.findFiles('fresh'), isEmpty);
      final provider = workbench.fileSystems.providerOf('mem')!;
      await provider.createFile(ResourceUri('mem'), 'fresh.txt');
      await Future<void>.delayed(Duration.zero);
      expect((await quickOpen.findFiles('fresh')).single.uri.path, '/fresh.txt');
    });

    test('命令搜索使用 分类: 标题 标签', () async {
      final host = ExtensionHost(workbench);
      addTearDown(host.dispose);
      host.registerFactory('demo.cap', () => _RecordingExtension([]));
      await host.sync([
        PluginInfo(
          id: 'demo',
          capability: 'demo.cap',
          enabled: true,
          contributes: _contributes(),
          activationEvents: const ['onCommand:demo.*'],
        ),
      ]);
      expect(quickOpen.findCommands('demo hello').first.command.command,
          'demo.hello');
      expect(quickOpen.findCommands('').length, greaterThan(1));
      expect(quickOpen.findCommands('qqqq'), isEmpty);
    });
  });
}

class _ReadOnlyProvider extends FileSystemProvider {
  @override
  String get scheme => 'ro';
  @override
  String get label => 'ro';
  @override
  bool get readOnly => true;
  @override
  Future<FileStat> stat(ResourceUri uri) async =>
      const FileStat(type: FileType.directory);
  @override
  Future<List<DirEntry>> readDirectory(ResourceUri uri) async => const [];
  @override
  Future<String> readText(ResourceUri uri) async => '';
}
