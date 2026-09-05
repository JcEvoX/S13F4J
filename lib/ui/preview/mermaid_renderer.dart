import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// 识别 ```mermaid / ~~~mermaid 围栏代码块，产出 `mermaid` 元素。
///
/// 该语法在 MarkdownBody 的 `blockSyntaxes` 中注册，优先级高于默认的
/// `FencedCodeBlockSyntax`，从而把 mermaid 代码块交给
/// [MermaidTagBuilder] 渲染，而普通代码块仍走默认高亮逻辑。
class MermaidBlockSyntax extends md.BlockSyntax {
  const MermaidBlockSyntax();

  static final RegExp _fence = RegExp(r'^\s*(`{3,}|~{3,})\s*mermaid\s*$');

  @override
  RegExp get pattern => _fence;

  @override
  md.Node parse(md.BlockParser parser) {
    final marker = pattern.firstMatch(parser.current.content)!.group(1)!;
    final opening = marker[0];
    final length = marker.length;

    final lines = <String>[];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      final close = RegExp('^\\s*${RegExp.escape(opening)}{$length,}\\s*\$')
          .firstMatch(line);
      if (close != null) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    final text = lines.join('\n');
    return md.Element('mermaid', [md.Text(text)]);
  }
}

/// 将 `mermaid` 元素渲染为 [MermaidDiagram]。
class MermaidTagBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return MermaidDiagram(definition: element.textContent);
  }
}

enum _Shape { rect, round, diamond }

class _MNode {
  _MNode(this.id, this.text, this.shape);
  final String id;
  final String text;
  final _Shape shape;
}

class _MEdge {
  _MEdge(this.from, this.to, {this.label = '', this.dashed = false});
  final String from;
  final String to;
  final String label;
  final bool dashed;
}

/// 解析并渲染简单的 Mermaid 流程图（`graph TD` / `graph LR`）。
///
/// 支持：节点定义 `A[文本]` `A(文本)` `A{文本}`，以及边 `A --> B`、
/// `A -- 标签 --> B`、`A --- B`、`A -.-> B`。复杂布局（subgraph、
/// 方向、换行等）当前做降级处理，仍可展示流程骨架。
class MermaidDiagram extends StatelessWidget {
  const MermaidDiagram({super.key, required this.definition});

  final String definition;

  @override
  Widget build(BuildContext context) {
    final parsed = _parse(definition);
    return _MermaidView(nodes: parsed.nodes, edges: parsed.edges);
  }

  /// 解析 Mermaid 定义文本。
  _MermaidData _parse(String src) {
    final nodes = <String, _MNode>{};
    final edges = <_MEdge>[];
    bool directionLr = false;

    for (final raw in src.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      // 图方向声明。
      if (line.startsWith('graph') || line.startsWith('flowchart')) {
        directionLr = line.contains('LR') || line.contains('RL');
        continue;
      }

      // 边定义：`A --> B`、`A --- B`、`A -.-> B`、`A -- label --> B`、
      // `A -->|label| B`。
      final edgeMatch = RegExp(r'^([\w\-]+)\s*(.*?)\s*([\w\-]+)$').firstMatch(line);
      if (edgeMatch != null) {
        final from = edgeMatch.group(1)!;
        final to = edgeMatch.group(3)!;
        final link = edgeMatch.group(2) ?? '-->';
        final dashed = link.contains('.-');
        // 标签：`-- 文本 -->` 或 `-->|文本|`。
        String label = '';
        final pipe = RegExp(r'\|(.*?)\|').firstMatch(link);
        if (pipe != null) {
          label = pipe.group(1) ?? '';
        } else {
          final dashLabel =
              RegExp(r'--\s*(.*?)\s*(?:-->|--|-|\.\.>)').firstMatch(link);
          if (dashLabel != null) {
            label = dashLabel.group(1) ?? '';
          }
        }
        edges.add(_MEdge(from, to, label: label.trim(), dashed: dashed));
        continue;
      }

      // 节点定义：`ID[文本]` / `ID(文本)` / `ID{文本}`。
      final nodeMatch =
          RegExp(r'^([\w\-]+)\s*[\[\(\{](.*)[\]\)\}]$').firstMatch(line);
      if (nodeMatch != null) {
        final id = nodeMatch.group(1)!;
        final text = nodeMatch.group(2)!.trim();
        final open = line[line.indexOf(id) + id.length];
        final shape = switch (open) {
          '{' => _Shape.diamond,
          '(' => _Shape.round,
          _ => _Shape.rect,
        };
        nodes[id] = _MNode(id, text.isEmpty ? id : text, shape);
        continue;
      }

      // 其它（例如 `id: text` 或 subgraph 声明）——尽力提取为文本节点。
      final colonMatch = RegExp(r'^([\w\-]+)\s*:\s*(.*)$').firstMatch(line);
      if (colonMatch != null) {
        nodes[colonMatch.group(1)!] =
            _MNode(colonMatch.group(1)!, colonMatch.group(2)!.trim(), _Shape.rect);
      }
    }

    return _MermaidData(nodes: nodes, edges: edges, directionLr: directionLr);
  }
}

class _MermaidData {
  _MermaidData({required this.nodes, required this.edges, required this.directionLr});
  final Map<String, _MNode> nodes;
  final List<_MEdge> edges;
  final bool directionLr;
}

class _MermaidView extends StatelessWidget {
  const _MermaidView({required this.nodes, required this.edges});

  final Map<String, _MNode> nodes;
  final List<_MEdge> edges;

  @override
  Widget build(BuildContext context) {
    // 依据边出现的先后顺序排布节点，保证箭头成链；未出现在边中的孤立节点
    // 追加到末尾。
    final ordered = <String>[];
    void ensure(String id) {
      if (!ordered.contains(id) && nodes.containsKey(id)) ordered.add(id);
    }

    for (final e in edges) {
      ensure(e.from);
      ensure(e.to);
    }
    for (final id in nodes.keys) {
      ensure(id);
    }
    if (ordered.isEmpty) {
      return _CodeFallback(definition: nodes.values.map((n) => n.text).join('\n'));
    }

    // label 查找表 (from,to) -> label。
    final labels = <(String, String), String>{};
    final dashedSet = <(String, String)>{};
    for (final e in edges) {
      labels[(e.from, e.to)] = e.label;
      if (e.dashed) dashedSet.add((e.from, e.to));
    }

    final widgets = <Widget>[];
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      final node = nodes[id]!;
      widgets.add(Center(child: _nodeWidget(node)));
      if (i < ordered.length - 1) {
        final next = ordered[i + 1];
        widgets.add(_connector(
          label: labels[(id, next)] ?? labels[(next, id)] ?? '',
          dashed: dashedSet.contains((id, next)) || dashedSet.contains((next, id)),
        ));
      }
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      ),
    );
  }

  Widget _nodeWidget(_MNode node) {
    switch (node.shape) {
      case _Shape.diamond:
        return Transform.rotate(
          angle: -0.785, // 45°，把方块旋成菱形
          child: _box(node.text, borderRadius: BorderRadius.circular(4)),
        );
      case _Shape.round:
        return _box(node.text, borderRadius: BorderRadius.circular(16));
      case _Shape.rect:
        return _box(node.text, borderRadius: BorderRadius.circular(4));
    }
  }

  Widget _box(String text, {required BorderRadius borderRadius}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        border: Border.all(color: const Color(0xFF607D8B)),
        borderRadius: borderRadius,
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }

  Widget _connector({
    required String label,
    required bool dashed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label.trim(),
                style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
          ),
        SizedBox(
          height: 20,
          child: CustomPaint(
            painter: _ArrowPainter(dashed: dashed),
            size: const Size(double.infinity, 20),
          ),
        ),
      ],
    );
  }
}

/// 向下的箭头连线。
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.dashed});
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width / 2, 0);
    final end = Offset(size.width / 2, size.height - 6);
    final paint = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (dashed) {
      final path = Path()..moveTo(start.dx, start.dy)..lineTo(end.dx, end.dy);
      for (final metric in path.computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          final part = metric.extractPath(
            d,
            (d + 6).clamp(0, metric.length),
          );
          canvas.drawPath(part, paint);
          d += 6 + 4;
        }
      }
    } else {
      canvas.drawLine(start, end, paint);
    }

    final head = Path()
      ..moveTo(end.dx - 5, end.dy - 2)
      ..lineTo(end.dx, end.dy + 5)
      ..lineTo(end.dx + 5, end.dy - 2)
      ..close();
    canvas.drawPath(head, Paint()..color = Colors.blueGrey);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.dashed != dashed;
}

/// 无法解析时的兜底展示（显示原始代码块，避免信息丢失）。
class _CodeFallback extends StatelessWidget {
  const _CodeFallback({required this.definition});
  final String definition;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(definition, style: const TextStyle(fontFamily: 'monospace')),
    );
  }
}