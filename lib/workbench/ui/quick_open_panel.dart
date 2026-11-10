import 'dart:async';

import 'package:flutter/material.dart';

import '../services/quick_open.dart';
import '../services/workbench.dart';
import 'icons.dart';

/// 打开命令面板 / 快速打开。宽屏为顶部浮层，窄屏为底部弹层。
Future<void> showQuickOpenPanel(
  BuildContext context, {
  required Workbench workbench,
  required QuickOpenService quickOpen,
  String initialText = '',
}) {
  final panel = QuickOpenPanel(
    workbench: workbench,
    quickOpen: quickOpen,
    initialText: initialText,
  );
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 600) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 440),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: panel,
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SizedBox(height: size.height * 0.7, child: panel),
    ),
  );
}

class _Item {
  const _Item({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onSelect,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Future<void> Function() onSelect;
}

class QuickOpenPanel extends StatefulWidget {
  const QuickOpenPanel({
    super.key,
    required this.workbench,
    required this.quickOpen,
    this.initialText = '',
  });

  final Workbench workbench;
  final QuickOpenService quickOpen;
  final String initialText;

  @override
  State<QuickOpenPanel> createState() => _QuickOpenPanelState();
}

class _QuickOpenPanelState extends State<QuickOpenPanel> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<_Item> _items = const [];
  bool _searching = false;
  int _generation = 0;

  Workbench get _wb => widget.workbench;
  bool get _commandMode => _controller.text.startsWith('>');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.selection =
        TextSelection.collapsed(offset: widget.initialText.length);
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), _refresh);
    setState(() {});
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    final text = _controller.text;
    if (text.startsWith('>')) {
      final matches = widget.quickOpen.findCommands(text.substring(1));
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _items = [
          for (final match in matches)
            _Item(
              icon: match.command.icon == null
                  ? Icons.chevron_right
                  : iconByName(match.command.icon),
              title: match.command.label,
              onSelect: () => _runCommand(match.command.command),
            ),
        ];
      });
      return;
    }
    setState(() => _searching = true);
    final matches = await widget.quickOpen.findFiles(text);
    if (!mounted || generation != _generation) return;
    setState(() {
      _searching = false;
      _items = [
        for (final match in matches)
          _Item(
            icon: iconForFile(match.uri.basename),
            title: _wb.titleFor(match.uri),
            subtitle: match.uri.toString(),
            onSelect: () async {
              await _wb.openResource(match.uri);
            },
          ),
      ];
    });
  }

  Future<void> _runCommand(String id) async {
    await _wb.executeCommand(id);
  }

  Future<void> _select(_Item item) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    try {
      await item.onSelect();
    } catch (e) {
      _wb.reportError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = _commandMode ? '输入命令名称…' : '按文件名搜索（输入 > 进入命令模式）';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            key: const ValueKey('quick-open-input'),
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (_) {
              if (_items.isNotEmpty) _select(_items.first);
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(_commandMode ? Icons.terminal : Icons.search),
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        Flexible(
          child: _items.isEmpty && !_searching
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _controller.text.trim().isEmpty && !_commandMode
                        ? '还没有最近文件。输入文件名搜索，或输入 > 查看全部命令。'
                        : '没有匹配项',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(item.icon, size: 20),
                      title: Text(item.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: item.subtitle == null
                          ? null
                          : Text(item.subtitle!,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      selected: index == 0,
                      onTap: () => _select(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
