import 'package:flutter/material.dart';

/// 原版 SaltNote 风格节点图标。
///
/// - 文件夹：橙色双色文件夹（#FFFFA000 页签 / #FFFFCA28 主体）
/// - 文章：灰色文档（带折角），默认使用原版 sub_text 灰，保证亮/暗主题均可见
class NodeIcon extends StatelessWidget {
  const NodeIcon({
    super.key,
    required this.isFolder,
    this.size = 22,
    this.documentColor,
  });

  final bool isFolder;
  final double size;

  /// 文章图标颜色（文件夹固定为原版橙色，不受此参数影响）。
  final Color? documentColor;

  /// 默认文章图标灰（取自原版 sub_text：#FF8B8C90）。
  static const Color defaultDocumentColor = Color(0xFF8B8C90);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: isFolder
          ? const _FolderPainter()
          : _DocumentPainter(documentColor ?? defaultDocumentColor),
    );
  }
}

// ---------------------------------------------------------------------------
// SVG path 解析（极简实现）
// ---------------------------------------------------------------------------

/// 解析原版矢量图标的 pathData，还原为 Flutter [Path]。
///
/// 支持 M/L/H/V/C/Q/S/T/Z 及其小写相对形式；图标中未涉及的指令
/// （如 A 圆弧）会被保守跳过，不影响已支持路径的绘制。
Path parseSvgPath(String data) {
  final path = Path();
  final tokens = _tokenize(data);
  var i = 0;
  var cmd = 'M';
  var cur = Offset.zero;
  var start = Offset.zero;

  double numAt(int idx) => tokens[idx] as double;

  while (i < tokens.length) {
    final t = tokens[i];
    if (t is String) {
      cmd = t;
      i++;
      continue;
    }
    switch (cmd) {
      case 'M':
      case 'm':
        final p = Offset(numAt(i), numAt(i + 1));
        i += 2;
        cur = cmd == 'M' ? p : cur + p;
        start = cur;
        path.moveTo(cur.dx, cur.dy);
        cmd = cmd == 'M' ? 'L' : 'l';
        break;
      case 'L':
      case 'l':
        final p = Offset(numAt(i), numAt(i + 1));
        i += 2;
        cur = cmd == 'L' ? p : cur + p;
        path.lineTo(cur.dx, cur.dy);
        break;
      case 'H':
      case 'h':
        final x = numAt(i);
        i += 1;
        cur = cmd == 'H' ? Offset(x, cur.dy) : Offset(cur.dx + x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
        break;
      case 'V':
      case 'v':
        final y = numAt(i);
        i += 1;
        cur = cmd == 'V' ? Offset(cur.dx, y) : Offset(cur.dx, cur.dy + y);
        path.lineTo(cur.dx, cur.dy);
        break;
      case 'C':
      case 'c':
        final c1 = Offset(numAt(i), numAt(i + 1));
        final c2 = Offset(numAt(i + 2), numAt(i + 3));
        final p = Offset(numAt(i + 4), numAt(i + 5));
        i += 6;
        final cp1 = cmd == 'C' ? c1 : cur + c1;
        final cp2 = cmd == 'C' ? c2 : cur + c2;
        cur = cmd == 'C' ? p : cur + p;
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, cur.dx, cur.dy);
        break;
      case 'Q':
      case 'q':
        final c = Offset(numAt(i), numAt(i + 1));
        final p = Offset(numAt(i + 2), numAt(i + 3));
        i += 4;
        final cq = cmd == 'Q' ? c : cur + c;
        cur = cmd == 'Q' ? p : cur + p;
        path.quadraticBezierTo(cq.dx, cq.dy, cur.dx, cur.dy);
        break;
      case 'S':
      case 's':
      case 'T':
      case 't':
        // 当前图标未使用平滑曲线，降级为直线段保证不丢点。
        final p = Offset(numAt(i), numAt(i + 1));
        i += 2;
        cur = cmd == 'S' || cmd == 'T' ? p : cur + p;
        path.lineTo(cur.dx, cur.dy);
        break;
      case 'Z':
      case 'z':
        path.close();
        cur = start;
        break;
      default:
        // 未知指令：跳过该 token，避免死循环。
        i++;
    }
  }
  return path;
}

List<Object> _tokenize(String data) {
  final tokens = <Object>[];
  final re = RegExp(r'([a-zA-Z])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)');
  for (final m in re.allMatches(data)) {
    final cmd = m.group(1);
    if (cmd != null) {
      tokens.add(cmd);
    } else {
      tokens.add(double.parse(m.group(2)!));
    }
  }
  return tokens;
}

// ---------------------------------------------------------------------------
// 图标路径与绘制
// ---------------------------------------------------------------------------

/// 原版图标统一视口（folder/document 均为 172x172）。
const double _kIconViewport = 172.0;

class _SvgIcons {
  static final Path folderBack = parseSvgPath(
    'M143.33,43h-64.5l-14.33,-14.33h-35.83c-7.88,0 -14.33,6.45 '
    '-14.33,14.33v28.67h143.33v-14.33c0,-7.88 -6.45,-14.33 '
    '-14.33,-14.33z',
  );
  static final Path folderFront = parseSvgPath(
    'M143.33,43h-114.67c-7.88,0 -14.33,6.45 -14.33,14.33v71.67c0,7.88 '
    '6.45,14.33 14.33,14.33h114.67c7.88,0 14.33,-6.45 14.33,-14.33v-71.67'
    'c0,-7.88 -6.45,-14.33 -14.33,-14.33z',
  );
  static final Path documentBody = parseSvgPath(
    'M139.75,57.33v89.58c0,3.96 -3.21,7.17 -7.17,7.17h-93.17c-3.96,0 '
    '-7.17,-3.21 -7.17,-7.17v-121.83c0,-3.96 3.21,-7.17 7.17,-7.17h60.92z',
  );
  static final Path documentFold = parseSvgPath(
    'M100.33,17.92v32.25c0,3.96 3.21,7.17 7.17,7.17h32.25z',
  );
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _kIconViewport;
    canvas.scale(scale, scale);
    canvas.drawPath(_SvgIcons.folderBack, Paint()..color = const Color(0xFFFFA000));
    canvas.drawPath(
        _SvgIcons.folderFront, Paint()..color = const Color(0xFFFFCA28));
  }

  @override
  bool shouldRepaint(covariant _FolderPainter oldDelegate) => false;
}

class _DocumentPainter extends CustomPainter {
  _DocumentPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _kIconViewport;
    canvas.scale(scale, scale);
    final paint = Paint()..color = color;
    canvas.drawPath(_SvgIcons.documentBody, paint);
    canvas.drawPath(_SvgIcons.documentFold, paint);
  }

  @override
  bool shouldRepaint(covariant _DocumentPainter oldDelegate) =>
      oldDelegate.color != color;
}
