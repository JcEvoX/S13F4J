import 'package:flutter/material.dart';

/// 插件安装/加载状态。
enum PluginState { installed, downloading, error }

/// 插件清单（插件包内 plugin.json 的内容）。
///
/// 插件是「声明式」的：只声明使用宿主内置的哪种能力（[capability]）以及
/// 展示信息/资源，逻辑由宿主的 [Capability] 实现执行。因此热插拔即时生效，
/// 且不存在动态代码，可安全通过 iOS 审核。
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.capability,
    this.icon = 'extension',
    this.builtin = false,
    this.author,
    this.downloadUrl,
    this.assets,
    this.namespace,
    bool? uninstallable,
    this.schema = 1,
    this.contributes,
    this.activationEvents = const [],
  }) : _uninstallable = uninstallable;

  /// 唯一标识，如 `builtin.notes`、`file.browser`。
  final String id;

  /// 显示名称，如「笔记」「文件系统」。
  final String name;
  final String version;
  final String description;

  /// 使用的宿主能力 id（如 `note.editor`、`file.browser`）。
  final String capability;

  /// Material Icons 名称（如 `note_alt`、`folder_open`）。
  final String icon;

  /// 是否随应用分发。内置插件默认不可卸载，可由 [uninstallable] 显式放开。
  final bool builtin;
  final String? author;

  /// 非内置插件：安装包下载地址。
  final String? downloadUrl;

  /// 插件包内携带的资源文件（相对路径，可选）。
  final List<String>? assets;

  /// 插件拥有的命名空间：id 等于该值，或以 `<namespace>.` 开头（如 `files.p-01`）。
  /// null 表示插件不持有持久数据。
  final String? namespace;

  /// 命名空间数据格式版本，随注册表记录一起保存。
  final int schema;

  /// 工作台贡献点（命令 / 菜单 / 视图 / 编辑器 / 状态栏），原样保存，
  /// 由 `lib/workbench` 解析（见 docs/workbench.md）。
  final Map<String, Object?>? contributes;

  /// 激活事件：`onStartup` / `onCommand:<id>` / `onResource:<scheme>` 等；空 = 启动时激活。
  final List<String> activationEvents;

  final bool? _uninstallable;

  /// 是否允许「卸载」。卸载 = 停用并保留数据（D9）；
  /// 未显式声明时，外部插件可卸载、内置插件不可卸载。
  bool get canUninstall => _uninstallable ?? !builtin;

  bool ownsNamespace(String namespaceId) {
    final ns = namespace;
    if (ns == null || ns.isEmpty) return false;
    return namespaceId == ns || namespaceId.startsWith('$ns.');
  }

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      description: json['description'] as String? ?? '',
      capability: json['capability'] as String? ?? '',
      icon: json['icon'] as String? ?? 'extension',
      builtin: json['builtin'] as bool? ?? false,
      author: json['author'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      assets: (json['assets'] as List?)?.cast<String>(),
      namespace: json['namespace'] as String?,
      uninstallable: json['uninstallable'] as bool?,
      schema: (json['schema'] as num?)?.toInt() ?? 1,
      contributes: (json['contributes'] as Map?)?.cast<String, Object?>(),
      activationEvents:
          (json['activationEvents'] as List?)?.whereType<String>().toList() ??
              const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'capability': capability,
        'icon': icon,
        'builtin': builtin,
        if (author != null) 'author': author,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        if (assets != null) 'assets': assets,
        if (namespace != null) 'namespace': namespace,
        if (_uninstallable != null) 'uninstallable': _uninstallable,
        'schema': schema,
        if (contributes != null) 'contributes': contributes,
        if (activationEvents.isNotEmpty) 'activationEvents': activationEvents,
      };
}

/// 已安装插件（清单 + 运行时状态）。
class InstalledPlugin {
  InstalledPlugin(
      {required this.manifest, this.enabled = true, this.downloadUrl});

  final PluginManifest manifest;

  /// 热插拔开关：启用/禁用即时生效，无需重启。
  bool enabled;

  /// 非内置插件的来源下载地址。
  String? downloadUrl;

  PluginState state = PluginState.installed;
  String? error;
}

/// 将插件清单中的图标名映射为 Material 图标。
IconData pluginIcon(String iconName) {
  switch (iconName) {
    case 'note_alt':
      return Icons.note_alt_outlined;
    case 'folder_open':
      return Icons.folder_open;
    case 'description':
      return Icons.description_outlined;
    default:
      return Icons.extension;
  }
}
