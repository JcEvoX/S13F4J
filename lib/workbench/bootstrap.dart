import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/notes_repository.dart';
import '../data/vault/vault_store.dart';
import '../plugins/plugin_manager.dart';
import '../services/namespace_registry.dart';
import 'extensions/core_extension.dart';
import 'extensions/files_extension.dart';
import 'extensions/notes_extension.dart';
import 'services/extension_host.dart';
import 'services/quick_open.dart';
import 'services/workbench.dart';

/// 会话保存在 shared_preferences（与其它设置同一后端）。
class SharedPrefsSessionStore implements SessionStore {
  static const _key = 'workbench.session';

  @override
  Future<Map<String, Object?>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  }

  @override
  Future<void> save(Map<String, Object?> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }
}

/// 工作台运行时：注册表 + 扩展宿主 + 快速打开，随应用生命周期存在。
class WorkbenchRuntime {
  WorkbenchRuntime._(this.workbench, this.host, this.quickOpen, this._plugins) {
    _plugins.addListener(_schedule);
  }

  final Workbench workbench;
  final ExtensionHost host;
  final QuickOpenService quickOpen;
  final PluginManager _plugins;

  Future<void> _chain = Future<void>.value();

  /// 从插件管理器当前状态对齐宿主；串行执行，避免连续启停时互相覆盖。
  Future<void> sync() {
    _chain = _chain.then((_) async {
      try {
        await host.sync([
          for (final plugin in _plugins.plugins)
            PluginInfo(
              id: plugin.manifest.id,
              capability: plugin.manifest.capability,
              enabled: plugin.enabled,
              contributes: plugin.manifest.contributes,
              activationEvents: plugin.manifest.activationEvents,
            ),
        ]);
        quickOpen.invalidate();
        await workbench.refreshWorkspace();
      } catch (e, stack) {
        debugPrint('[Workbench] 同步插件失败: $e\n$stack');
      }
    });
    return _chain;
  }

  void _schedule() => unawaited(sync());

  void dispose() {
    _plugins.removeListener(_schedule);
    quickOpen.dispose();
    host.dispose();
    workbench.dispose();
  }
}

/// 创建并启动工作台运行时。
///
/// [vaultStore] 为空表示数据后端回退到 sqlite：此时只有笔记一个工作区文件夹。
Future<WorkbenchRuntime> createWorkbenchRuntime({
  required NotesRepository repository,
  required PluginManager plugins,
  VaultStore? vaultStore,
  SessionStore? sessionStore,
}) async {
  final workbench =
      Workbench(sessionStore: sessionStore ?? SharedPrefsSessionStore());
  final host = ExtensionHost(workbench)
    ..registerFactory(kCorePluginId, CoreExtension.new)
    ..registerFactory('note.editor', () => NotesExtension(repository))
    ..registerFactory('file.browser', FilesExtension.new)
    ..registerAlwaysOn(coreExtensionInfo());

  workbench.workspaceFolderSource = () async {
    bool pluginEnabled(String pluginId) =>
        plugins.byId(pluginId)?.enabled ?? true;
    if (vaultStore == null) {
      return [
        WorkspaceFolder(
          scheme: 'notes',
          name: '笔记',
          state: pluginEnabled('builtin.notes') ? 'active' : 'disabled',
        ),
      ];
    }
    final registry = NamespaceRegistry(store: vaultStore);
    final namespaces = await registry.all();
    return [
      for (final ns in namespaces)
        WorkspaceFolder(
          scheme: ns.id,
          name: ns.displayName,
          // 插件开关即时生效；注册表状态随后由 onPluginStateChanged 落盘。
          state: !pluginEnabled(ns.pluginId) ? 'disabled' : ns.state,
        ),
    ];
  };

  final quickOpen = QuickOpenService(workbench);
  final runtime = WorkbenchRuntime._(workbench, host, quickOpen, plugins);
  await runtime.sync();
  return runtime;
}
