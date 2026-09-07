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
  });

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

  /// 是否随应用分发（内置插件不可卸载）。
  final bool builtin;
  final String? author;

  /// 非内置插件：安装包下载地址。
  final String? downloadUrl;

  /// 插件包内携带的资源文件（相对路径，可选）。
  final List<String>? assets;

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
      };
}

/// 已安装插件（清单 + 运行时状态）。
class InstalledPlugin {
  InstalledPlugin({required this.manifest, this.enabled = true, this.downloadUrl});

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
