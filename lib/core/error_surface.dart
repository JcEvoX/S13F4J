import 'package:flutter/material.dart';

/// 构建失败时的占位界面：除了异常信息，再带上调用栈前几行。
///
/// Flutter 默认的红屏只有一句断言文本，定位不了「是谁触发的」；
/// 带上栈后，截图就足够判断问题出在哪个组件。
void installErrorSurface() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final stack = details.stack
            ?.toString()
            .split('\n')
            .where((line) =>
                line.contains('package:notepad') || line.startsWith('#'))
            .take(14)
            .join('\n') ??
        '';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF8B0000),
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
        child: SingleChildScrollView(
          child: SelectableText(
            '${details.exception}\n\n$stack',
            style: const TextStyle(
              color: Color(0xFFFFFF66),
              fontSize: 11,
              fontFamily: 'monospace',
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  };
}
