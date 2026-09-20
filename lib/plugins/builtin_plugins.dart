import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/capability.dart';
import '../plugins/plugin_model.dart';
import '../state/note_provider.dart';
import '../ui/editor/editor_page.dart';
import '../ui/plugins/file_browser_page.dart';

/// 内置插件清单：笔记（默认能力）与文件系统读取随应用分发。
///
/// 两个内置插件也在插件仓库发布了对应安装包，可在插件中心卸载后
/// 从市场重新安装，验证「从 GitHub 下载插件」的完整链路。
PluginManifest builtinNotesPlugin() => const PluginManifest(
      id: 'builtin.notes',
      name: '笔记',
      version: '1.0.0',
      description: '默认笔记能力：Markdown 文本编辑、预览与文件夹组织。',
      capability: 'note.editor',
      icon: 'note_alt',
      builtin: true,
      author: 'JcEvoX',
    );

PluginManifest builtinFileBrowserPlugin() => const PluginManifest(
      id: 'builtin.files',
      name: '文件系统',
      version: '1.0.0',
      description: '通过系统文件选择器（SAF）读取本地文件/文档内容。',
      capability: 'file.browser',
      icon: 'folder_open',
      builtin: true,
      author: 'JcEvoX',
    );

/// 注册宿主内置能力（应用启动时调用一次）。
void registerBuiltinCapabilities() {
  capabilities
    ..register(_NoteEditorCapability())
    ..register(_FileBrowserCapability());
}

/// 笔记编辑能力：新建笔记并进入编辑器。
class _NoteEditorCapability extends Capability {
  @override
  String get id => 'note.editor';

  @override
  String get name => '笔记编辑器';

  @override
  String get description => '创建并编辑 Markdown 笔记';

  @override
  IconData get icon => Icons.note_alt_outlined;

  @override
  Future<void> launch(BuildContext context, PluginManifest manifest) async {
    final provider = context.read<NoteProvider>();
    final node = await provider.createNode(isFolder: false, title: '未命名');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorPage(nodeId: node.id)),
    );
  }
}

/// 文件系统读取能力：通过系统文件选择器读取文件内容。
class _FileBrowserCapability extends Capability {
  @override
  String get id => 'file.browser';

  @override
  String get name => '文件系统读取';

  @override
  String get description => '读取设备中的文件/文档';

  @override
  IconData get icon => Icons.folder_open;

  @override
  Future<void> launch(BuildContext context, PluginManifest manifest) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FileBrowserPage()),
    );
  }
}
