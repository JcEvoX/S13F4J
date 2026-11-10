import 'dart:async';

import 'package:flutter/foundation.dart';

import '../base/disposable.dart';
import 'command_registry.dart';
import 'contribution_registry.dart';
import 'editor_registry.dart';
import 'file_system.dart';
import 'view_registry.dart';
import 'workbench.dart';

/// 宿主内置的能力实现（随应用分发；插件包只带 manifest，D8）。
abstract class HostExtension {
  FutureOr<void> activate(ExtensionContext context);

  FutureOr<void> deactivate() {}
}

/// 能力在激活时拿到的上下文。所有注册都返回 [Disposable]，
/// 并自动进入 [subscriptions]，插件停用时由宿主统一释放。
class ExtensionContext {
  ExtensionContext._(this.pluginId, this.workbench);

  final String pluginId;
  final Workbench workbench;
  final DisposableStore subscriptions = DisposableStore();
  final Set<String> _schemes = {};
  final Set<String> _contextKeys = {};

  /// 该能力注册过的文件系统 scheme（停用时用来关闭对应标签）。
  Set<String> get registeredSchemes => Set.unmodifiable(_schemes);

  Disposable registerCommand(String id, CommandHandler handler) =>
      subscriptions.add(workbench.commands.register(id, handler));

  Disposable registerFileSystemProvider(FileSystemProvider provider) {
    _schemes.add(provider.scheme);
    final registration = workbench.fileSystems.register(provider);
    return subscriptions.add(
      toDisposable(() {
        registration.dispose();
        provider.dispose();
      }),
    );
  }

  Disposable registerEditorProvider(String viewType, EditorBuilder builder) =>
      subscriptions.add(workbench.editors.register(viewType, builder));

  Disposable registerViewProvider(String viewId, ViewBuilder builder) =>
      subscriptions.add(workbench.views.register(viewId, builder));

  /// 写入上下文键；停用时自动清除。
  void setContext(String key, Object? value) {
    _contextKeys.add(key);
    workbench.contextKeys.set(key, value);
  }

  void _clearContext() {
    for (final key in _contextKeys) {
      workbench.contextKeys.remove(key);
    }
    _contextKeys.clear();
  }
}

/// 宿主眼里的插件：与 `PluginManager` 解耦，避免 workbench 依赖 plugins。
class PluginInfo {
  const PluginInfo({
    required this.id,
    required this.capability,
    required this.enabled,
    this.contributes,
    this.activationEvents = const [],
  });

  final String id;

  /// 对应的 `HostExtension` 工厂 id；没有工厂即纯声明式插件。
  final String capability;
  final bool enabled;
  final Map<String, Object?>? contributes;
  final List<String> activationEvents;

  String get signature =>
      '$capability|${contributes ?? const {}}|$activationEvents';
}

class _Entry {
  _Entry(this.info, this.contributions);

  PluginInfo info;
  PluginContributions contributions;
  HostExtension? extension;
  ExtensionContext? context;
  Future<void>? activating;
  bool active = false;
  String? error;
}

/// 扩展宿主：按插件启停同步贡献，按激活事件懒激活，停用即释放。
class ExtensionHost extends ChangeNotifier {
  ExtensionHost(this.workbench) {
    workbench.extensionHost = this;
  }

  final Workbench workbench;
  final Map<String, HostExtension Function()> _factories = {};
  final Map<String, _Entry> _entries = {};
  final Map<String, PluginInfo> _alwaysOn = {};

  void registerFactory(String capabilityId, HostExtension Function() factory) {
    _factories[capabilityId] = factory;
  }

  /// 宿主自带、始终启用的「插件」（如 workbench.core）。
  void registerAlwaysOn(PluginInfo info) {
    _alwaysOn[info.id] = PluginInfo(
      id: info.id,
      capability: info.capability,
      enabled: true,
      contributes: info.contributes,
      activationEvents: info.activationEvents,
    );
  }

  bool isActive(String pluginId) => _entries[pluginId]?.active ?? false;

  String? errorOf(String pluginId) => _entries[pluginId]?.error;

  Iterable<String> get knownPlugins => _entries.keys;

  /// 声明匹配：`*` / `onStartup` 只响应 `onStartup`；末尾 `*` 为前缀匹配。
  static bool matchesEvent(String declared, String fired) {
    if (declared == fired) return true;
    if (declared == '*') return fired == 'onStartup';
    if (declared.endsWith('*')) {
      return fired.startsWith(declared.substring(0, declared.length - 1));
    }
    return false;
  }

  bool _listens(_Entry entry, String event) {
    final events = entry.info.activationEvents.isEmpty
        ? const ['onStartup']
        : entry.info.activationEvents;
    return events.any((declared) => matchesEvent(declared, event));
  }

  /// 是否有尚未激活、且监听该事件的插件。
  bool canActivateFor(String event) => _entries.values.any(
        (e) => !e.active && e.error == null && _listens(e, event),
      );

  /// 对齐插件列表：新增 / 变更 / 移除，并触发 `onStartup`。
  Future<void> sync(List<PluginInfo> plugins) async {
    final desired = <String, PluginInfo>{
      ..._alwaysOn,
      for (final plugin in plugins)
        if (plugin.enabled) plugin.id: plugin,
    };

    for (final id in _entries.keys.toList()) {
      final next = desired[id];
      if (next == null || next.signature != _entries[id]!.info.signature) {
        await _remove(id);
      }
    }
    for (final info in desired.values) {
      if (_entries.containsKey(info.id)) continue;
      final contributions =
          PluginContributions.parse(info.id, info.contributes);
      _entries[info.id] = _Entry(info, contributions);
      workbench.contributions.setPlugin(info.id, contributions);
    }
    notifyListeners();
    await activateByEvent('onStartup');
  }

  Future<void> activateByEvent(String event) async {
    final targets = [
      for (final entry in _entries.values)
        if (!entry.active && entry.error == null && _listens(entry, event))
          entry,
    ];
    await Future.wait([for (final entry in targets) _activate(entry)]);
  }

  Future<void> _activate(_Entry entry) {
    return entry.activating ??= _doActivate(entry).whenComplete(() {
      entry.activating = null;
    });
  }

  Future<void> _doActivate(_Entry entry) async {
    // 激活常由 Widget 的 initState（如会话恢复的标签）触发；先让出一个微任务，
    // 保证扩展注册 / 通知不会发生在构建阶段内（否则 setState during build）。
    await Future<void>.value();
    if (entry.active) return;
    final factory = _factories[entry.info.capability];
    if (factory == null) {
      entry.active = true;
      notifyListeners();
      return;
    }
    final context = ExtensionContext._(entry.info.id, workbench);
    final extension = factory();
    try {
      await extension.activate(context);
      entry.extension = extension;
      entry.context = context;
      entry.active = true;
    } catch (e, stack) {
      debugPrint('[ExtensionHost] 激活失败 ${entry.info.id}: $e\n$stack');
      entry.error = '$e';
      context.subscriptions.dispose();
      context._clearContext();
    }
    notifyListeners();
  }

  Future<void> _remove(String pluginId) async {
    final entry = _entries.remove(pluginId);
    if (entry == null) return;
    try {
      await entry.extension?.deactivate();
    } catch (e) {
      debugPrint('[ExtensionHost] 停用回调失败 $pluginId: $e');
    }
    final schemes = entry.context?.registeredSchemes ?? const <String>{};
    entry.context?.subscriptions.dispose();
    entry.context?._clearContext();
    workbench.contributions.removePlugin(pluginId);
    for (final scheme in schemes) {
      workbench.closeTabsOfScheme(scheme);
    }
  }

  @override
  void dispose() {
    for (final id in _entries.keys.toList()) {
      final entry = _entries.remove(id)!;
      entry.context?.subscriptions.dispose();
    }
    super.dispose();
  }
}
