import 'package:flutter/material.dart';

/// 编辑器区域内的统一提示（加载失败 / 资源不存在 / 无可用编辑器）。
class EditorMessage extends StatelessWidget {
  const EditorMessage({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.actions = const [],
  });

  final String message;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center, style: TextStyle(color: color)),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
