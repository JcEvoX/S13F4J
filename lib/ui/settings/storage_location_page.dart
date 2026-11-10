import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../services/storage_paths.dart';
import '../../services/vault_relocator.dart';
import '../storage_access_dialog.dart';

/// 选择文档库存放位置。
///
/// 既用于首次启动 / 授权失效时的启动前引导，也用于设置里的「存储位置」。
/// 切换时会把现有笔记复制到新位置（不删除旧位置的数据），完成后写入设置。
class StorageLocationPage extends StatefulWidget {
  const StorageLocationPage({
    super.key,
    required this.settings,
    required this.onDone,
    this.reason,
    this.canCancel = false,
  });

  final SettingsService settings;

  /// 切换完成：带回最终位置与给用户看的结果说明。
  final void Function(StorageLocation location, String message) onDone;

  /// 为什么出现这个页面（例如授权被撤销）。
  final String? reason;
  final bool canCancel;

  @override
  State<StorageLocationPage> createState() => _StorageLocationPageState();
}

class _StorageLocationPageState extends State<StorageLocationPage> {
  late StorageLocation _selected;
  String? _internalRoot;
  String? _publicRoot;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.settings.storageLocation;
    _selected = !StoragePaths.documentsLocationAvailable
        ? StorageLocation.internal
        : saved ?? StorageLocation.documents;
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final internal = await StoragePaths.internalVaultRoot();
    final public = await StoragePaths.publicVaultRoot();
    if (!mounted) return;
    setState(() {
      _internalRoot = internal;
      _publicRoot = public;
    });
  }

  Future<String> _currentRoot() async {
    final internal = _internalRoot ?? await StoragePaths.internalVaultRoot();
    if (widget.settings.storageLocation == StorageLocation.documents) {
      return _publicRoot ?? await StoragePaths.publicVaultRoot() ?? internal;
    }
    return internal;
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_selected == StorageLocation.documents) {
        final granted = await ensureStorageAccessWithDialog(
          context,
          purpose: '把笔记保存到「文档/NotePad」',
        );
        if (!granted) {
          _fail('没有获得文件访问权限，无法保存到公共文档目录。');
          return;
        }
      }
      final from = await _currentRoot();
      final to = _selected == StorageLocation.documents
          ? await StoragePaths.publicVaultRoot()
          : await StoragePaths.internalVaultRoot();
      if (to == null) {
        _fail('找不到公共文档目录。');
        return;
      }
      final result = await VaultRelocator.copyVault(from, to);
      await widget.settings.setStorageLocation(_selected);
      if (!mounted) return;
      final message = result.targetAlreadyHadData && from != to
          ? '目标位置已有笔记，已直接使用，没有覆盖：$to'
          : result.copiedFiles > 0
              ? '已把 ${result.copiedFiles} 个文件复制到 $to'
              : '笔记将保存在 $to';
      widget.onDone(_selected, message);
    } catch (e) {
      _fail('切换失败：$e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <_LocationOption>[
      if (StoragePaths.documentsLocationAvailable)
        _LocationOption(
          location: StorageLocation.documents,
          title: '文档/NotePad（推荐）',
          path: _publicRoot ?? '/storage/emulated/0/Documents/NotePad',
          description: '笔记是普通的 Markdown 文件，文件管理器、同步工具可直接访问；'
              '卸载应用也不会丢。需要「所有文件访问」权限。',
          icon: Icons.folder_shared_outlined,
        ),
      _LocationOption(
        location: StorageLocation.internal,
        title: '仅应用内部',
        path: _internalRoot ?? '应用私有目录',
        description: '不需要任何权限，但只有本应用能看到，卸载应用会一并删除。',
        icon: Icons.lock_outline,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('存储位置'),
        automaticallyImplyLeading: widget.canCancel,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('笔记存放在哪里？', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              widget.reason ?? '现有笔记会被复制到新位置，原位置的数据不会被删除。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final option in options)
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _selected == option.location
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                    width: _selected == option.location ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  key: ValueKey('storage-${option.location.name}'),
                  onTap: _busy
                      ? null
                      : () => setState(() => _selected = option.location),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(option.icon, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.title,
                                  style: theme.textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(option.path,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  )),
                              const SizedBox(height: 6),
                              Text(option.description,
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Icon(
                          _selected == option.location
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.canCancel)
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.maybePop(context),
                    child: const Text('取消'),
                  ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('storage-apply'),
                  onPressed: _busy ? null : _apply,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationOption {
  const _LocationOption({
    required this.location,
    required this.title,
    required this.path,
    required this.description,
    required this.icon,
  });

  final StorageLocation location;
  final String title;
  final String path;
  final String description;
  final IconData icon;
}
