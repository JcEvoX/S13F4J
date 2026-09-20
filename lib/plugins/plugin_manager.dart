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
  SharedPreferences? _prefs;
  Directory? _pluginsDir;

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

  /// 注册内置插件（随应用分发，默认启用、不可卸载）。
  void registerBuiltin(PluginManifest manifest) {
    if (byId(manifest.id) != null) return;
    _plugins.add(InstalledPlugin(manifest: manifest, enabled: true));
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
  }

  /// 卸载外部插件（内置插件不可卸载）。
  Future<void> uninstall(String id) async {
    final p = byId(id);
    if (p == null || p.manifest.builtin) return;
    _plugins.remove(p);
    if (_pluginsDir != null) {
      final dir = Directory('${_pluginsDir!.path}/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await _save();
    notifyListeners();
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
      for (final p in _plugins) {
        p.enabled = map[p.manifest.id] as bool? ?? true;
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
