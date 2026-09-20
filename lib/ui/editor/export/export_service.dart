import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 导出类型。
enum ExportKind { image, text, markdown, pdf }

/// 导出服务。
///
/// 对应原 Android 端基于存储访问框架（SAF）的导出能力。跨平台统一使用
/// `file_selector`（移动 / 桌面通用），持久化为 txt / md / pdf / 图片。
class ExportService {
  /// 执行导出。图片导出基于 [renderBoundary] 的 RepaintBoundary 截图。
  Future<void> export(
    BuildContext context, {
    required ExportKind kind,
    required String title,
    required String content,
    GlobalKey? renderBoundary,
  }) async {
    switch (kind) {
      case ExportKind.text:
        await _exportText(title, content);
        break;
      case ExportKind.markdown:
        await _exportMarkdown(title, content);
        break;
      case ExportKind.pdf:
        await _exportPdf(title, content);
        break;
      case ExportKind.image:
        await _exportImage(title, renderBoundary);
        break;
    }
  }

  String _safeName(String title) {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return clean.isEmpty ? '未命名' : clean;
  }

  /// 弹窗选择保存路径，返回实际文件路径（null 表示取消）。
  Future<String?> _pickPath(String name) async {
    const group = XTypeGroup(label: 'file', extensions: []);
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: <XTypeGroup>[group],
    );
    return location?.path;
  }

  Future<void> _exportText(String title, String content) async {
    final path = await _pickPath('${_safeName(title)}.txt');
    if (path == null) return;
    await File(path).writeAsString(content);
  }

  Future<void> _exportMarkdown(String title, String content) async {
    final path = await _pickPath('${_safeName(title)}.md');
    if (path == null) return;
    await File(path).writeAsString(content);
  }

  Future<void> _exportPdf(String title, String content) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: pw.Font.courier()),
        build: (_) => [
          pw.Header(
            child: pw.Text(title,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
          ),
          pw.SizedBox(height: 8),
          pw.Paragraph(text: content),
        ],
      ),
    );
    final bytes = await doc.save();
    final path = await _pickPath('${_safeName(title)}.pdf');
    if (path == null) return;
    await File(path).writeAsBytes(bytes);
  }

  Future<void> _exportImage(String title, GlobalKey? key) async {
    if (key == null || key.currentContext == null) return;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final path = await _pickPath('${_safeName(title)}.png');
    if (path == null) return;
    await File(path).writeAsBytes(byteData.buffer.asUint8List());
  }
}