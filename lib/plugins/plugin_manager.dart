import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_model.dart';

/// 插件管理器：维护已安装插件（内置 + 外部下载），
/// 支持热插拔（启用/禁用即时生效）与卸载。
///
/// 内置插件随应用分发、默认启用且不可卸载；外部插件从插件市场
/// 下载 zip 安装包（含 plugin.json 与资源），解压到应用支持目录。
class PluginManager extends ChangeNotifier {
  PluginManager._();

  static final PluginManager instance = PluginManager._();

  static const _kInstalled = 'plugins.installed';
  static const _kEnabled = 'plugins.enabled';

  final List<InstalledPlugin> _plugins = [];
  Map<String, bool> _persistedEnabled = {};
  SharedPreferences? _prefs;
  Directory? _pluginsDir;

  /// 插件启停回调：由启动流程注入，用于同步命名空间注册表状态。
  Future<void> Function(String pluginId, bool active)? onPluginStateChanged;

  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  /// 当前启用的插件（热插拔后即时反映）。
  List<InstalledPlugin> get enabledPlugins =>
      _plugins.where((p) => p.enabled).toList();

  InstalledPlugin? byId(String id) {
    for (final p in _plugins) {
      if (p.manifest.id == id) return p;
    }
    return null;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    _pluginsDir = Directory('${support.path}/plugins');
    await _pluginsDir!.create(recursive: true);
    _loadFromPrefs();
    notifyListeners();
  }

  /// 注册内置插件（随应用分发，默认启用；启停状态从持久化设置恢复）。
  void registerBuiltin(PluginManifest manifest) {
    if (byId(manifest.id) != null) return;
    _plugins.add(
      InstalledPlugin(
        manifest: manifest,
        enabled: _persistedEnabled[manifest.id] ?? true,
      ),
    );
    notifyListeners();
  }

  /// 从插件包（zip 字节）安装插件；已存在同 id 时覆盖。
  Future<void> installFromZip(List<int> bytes, {String? downloadUrl}) async {
    if (_pluginsDir == null) {
      throw StateError('PluginManager 尚未初始化');
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? manifestEntry;
    for (final f in archive.files) {
      if (f.isFile && f.name == 'plugin.json') {
        manifestEntry = f;
        break;
      }
    }
    if (manifestEntry == null) {
      throw const FormatException('插件包缺少 plugin.json');
    }
    final manifest = PluginManifest.fromJson(
      jsonDecode(utf8.decode(manifestEntry.content as List<int>))
          as Map<String, dynamic>,
    );
    if (manifest.id.isEmpty) {
      throw const FormatException('插件 manifest.id 为空');
    }
    // 覆盖安装：移除旧实例并清空旧目录。
    _plugins.removeWhere((p) => p.manifest.id == manifest.id);
    final dir = Directory('${_pluginsDir!.path}/${manifest.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final file = File('${dir.path}/${f.name}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(f.content as List<int>);
    }
    _plugins.add(
      InstalledPlugin(
        manifest: manifest,
        enabled: true,
        downloadUrl: downloadUrl ?? manifest.downloadUrl,
      ),
    );
    await _save();
    notifyListeners();
  }

  /// 热插拔：启用/禁用插件（即时生效，无需重启）。
  Future<void> setEnabled(String id, bool enabled) async {
    final p = byId(id);
    if (p == null) return;
    p.enabled = enabled;
    await _save();
    notifyListeners();
    await onPluginStateChanged?.call(p.manifest.id, enabled);
  }

  /// 卸载插件：停用并保留数据（D9）。
  ///
  /// 外部插件额外删除插件包资源；内置插件随应用分发，仅停用。
  /// 命名空间、回收站与备份一律保留，重新启用 / 安装后入口与数据自动恢复。
  Future<void> uninstall(String id) async {
    final p = byId(id);
    if (p == null || !p.manifest.canUninstall) return;
    p.enabled = false;
    if (!p.manifest.builtin && _pluginsDir != null) {
      final dir = Directory('${_pluginsDir!.path}/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await _save();
    notifyListeners();
    await onPluginStateChanged?.call(id, false);
  }

  void _loadFromPrefs() {
    final raw = _prefs?.getString(_kInstalled);
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        final map = (e as Map).cast<String, dynamic>();
        _plugins.add(
          InstalledPlugin(
            manifest: PluginManifest.fromJson(
              (map['manifest'] as Map).cast<String, dynamic>(),
            ),
            downloadUrl: map['downloadUrl'] as String?,
          ),
        );
      }
    }
    final enabledRaw = _prefs?.getString(_kEnabled);
    if (enabledRaw != null && enabledRaw.isNotEmpty) {
      final map = jsonDecode(enabledRaw) as Map<String, dynamic>;
      _persistedEnabled = {
        for (final e in map.entries)
          if (e.value is bool) e.key: e.value as bool,
      };
      for (final p in _plugins) {
        p.enabled = _persistedEnabled[p.manifest.id] ?? true;
      }
    }
  }

  Future<void> _save() async {
    final external = _plugins.where((p) => !p.manifest.builtin).toList();
    await _prefs?.setString(
      _kInstalled,
      jsonEncode([
        for (final p in external)
          {
            'manifest': p.manifest.toJson(),
            if (p.downloadUrl != null) 'downloadUrl': p.downloadUrl,
          },
      ]),
    );
    await _prefs?.setString(
      _kEnabled,
      jsonEncode({for (final p in _plugins) p.manifest.id: p.enabled}),
    );
  }
}
