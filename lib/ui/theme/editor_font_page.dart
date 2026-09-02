import 'package:flutter/material.dart';

import '../../services/settings_service.dart';

/// 编辑器字体设置页。
///
/// 对应原 Android 端的「编辑器字体」：支持字体族选择、字号调整
/// 与「恢复默认」。字号 / 字体写入设置，编辑器实时读取生效。
class EditorFontPage extends StatefulWidget {
  const EditorFontPage({super.key});

  @override
  State<EditorFontPage> createState() => _EditorFontPageState();
}

class _EditorFontPageState extends State<EditorFontPage> {
  SettingsService? _settings;
  double _size = 17;
  String _family = 'system';

  static const _families = <(String, String, String)>[
    ('system', '系统默认', 'Roboto / SF Pro'),
    ('serif', '衬线体', 'Serif'),
    ('monospace', '等宽字体', 'Monospace'),
    ('cursive', '手写体', 'Cursive'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsService.instance;
    if (!mounted) return;
    setState(() {
      _settings = s;
      _size = s.editorFontSize;
      _family = s.editorFontFamily;
    });
  }

  Future<void> _saveSize(double v) async {
    _size = v;
    await _settings!.setEditorFontSize(v);
  }

  Future<void> _saveFamily(String v) async {
    _family = v;
    await _settings!.setEditorFontFamily(v);
  }

  Future<void> _reset() async {
    await _settings!.resetEditorFont();
    if (!mounted) return;
    setState(() {
      _size = 17;
      _family = 'system';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑器字体'),
        actions: [
          TextButton(
            onPressed: s == null ? null : _reset,
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _previewCard(),
                const SizedBox(height: 24),
                const Text('正文字体大小',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _size,
                        min: 12,
                        max: 32,
                        divisions: 40,
                        label: '${_size.round()}',
                        onChanged: (v) => setState(() => _size = v),
                        onChangeEnd: _saveSize,
                      ),
                    ),
                    Text('${_size.round()}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('字体族',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _family,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _family = v);
                    _saveFamily(v);
                  },
                  child: Column(
                    children: [
                      for (final (key, name, desc) in _families)
                        RadioListTile<String>(
                          value: key,
                          dense: true,
                          title: Text(name,
                              style: TextStyle(
                                  fontFamily:
                                      key == 'system' ? null : key)),
                          subtitle: Text(desc,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _previewCard() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'NotePad\n这是编辑器字体预览：明月几时有，把酒问青天。\n# 标题 **加粗** 等等 Markdown 元素。',
          style: TextStyle(
            fontSize: _size,
            height: 1.6,
            fontFamily: _family == 'system' ? null : _family,
          ),
        ),
      ),
    );
  }
}
