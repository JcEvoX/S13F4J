import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// 行内数学语法：匹配 `$...$`，产出 `math` 元素。
///
/// 先不匹配 `$$`（这是块级公式），避免与[LatexDisplayInlineSyntax]冲突。
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax()
      : super(
          r'(?<!\$)\$([^\$\n]+?)\$(?!\$)',
          startCharacter: 0x24, // '$'
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = (match.group(1) ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(md.Element.text('math', tex));
    return true;
  }
}

/// 块级数学语法：匹配 `$$...$$` 或 `\[...\]`，产出 `math-block` 元素。
///
/// 置于[LatexInlineSyntax]之前尝试，这样 `$$` 会先被整体消费。
class LatexDisplayInlineSyntax extends md.InlineSyntax {
  LatexDisplayInlineSyntax()
      : super(
          r'(?:\$\$([\s\S]+?)\$\$)|(?:\\\[([\s\S]+?)\\\])',
        );
  // startCharacter 不设：块级公式可能以 '$' 或 '\' 开头。

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = (match.group(1) ?? match.group(2) ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(md.Element.text('math-block', tex));
    return true;
  }
}

/// 将 `math` / `math-block` 元素渲染为 TeX 公式。
class LatexElementBuilder extends MarkdownElementBuilder {
  LatexElementBuilder({this.display = false});

  /// 是否为块级（居中、加大字号）公式。
  final bool display;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    if (tex.isEmpty) return null;

    final style = preferredStyle ??
        parentStyle ??
        DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 16));
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style,
    );

    if (!display) return math;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: math,
    );
  }
}