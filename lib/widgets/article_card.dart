import 'package:flutter/material.dart';

import '../models/note.dart';
import 'node_icon.dart';

/// 原版 SaltNote 列表项卡片（对应 recycler_article.xml / recycler_article_folder.xml）。
///
/// - 外层 16dip 横向 / 4dip 纵向留白
/// - 卡片圆角 12dip、无阴影、半透明白底（壁纸可透出）
/// - 文章：图标 + 粗体标题 / 内容预览（最多 2 行，sub_text 灰）/ 时间副文本（11sp 半透明）
/// - 文件夹：图标 + 粗体标题 / 副文本（11sp 半透明）
/// - 右侧 48dip 留给 [trailing]（more_vert / 多选勾选 / 拖拽把手）
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.node,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.subtitle,
    this.time,
    this.contentEndPadding = 48,
  });

  final NotePadNode node;

  /// 内容区右侧预留宽度（给 trailing 让位，默认 48dip）。
  final double contentEndPadding;

  /// 点击回调（打开 / 多选切换）。
  final VoidCallback onTap;

  /// 长按回调（进入多选）。
  final VoidCallback? onLongPress;

  /// 右侧操作区（原版 ivMoreVert 位置）。
  final Widget? trailing;

  /// 是否选中（多选模式下高亮）。
  final bool selected;

  /// 副文本：文章传内容预览，文件夹传数量等；为 null 时自动按类型生成。
  final String? subtitle;

  /// 文章的时间副文本（原版 tvSub，11sp 半透明）。仅文章显示。
  final String? time;

  /// 原版正文色。
  static const Color _textColor = Color(0xFF191B23);

  /// 原版副文本灰。
  static const Color _subTextColor = Color(0xFF8B8C90);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : _textColor;
    final scheme = Theme.of(context).colorScheme;

    final String sub;
    if (subtitle != null) {
      sub = subtitle!;
    } else if (node.isFolder) {
      sub = '文件夹';
    } else {
      sub = _preview(node.content);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        // 半透明白底（原版 translucent_background），深色下用更淡的白。
        color: isDark ? const Color(0x14FFFFFF) : const Color(0x80FFFFFF),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              // 内容区：右缘预留宽度给 trailing。
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 14,
                  top: 10,
                  end: contentEndPadding,
                  bottom: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        NodeIcon(isFolder: node.isFolder, size: 20),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            node.title.isEmpty ? '未命名' : node.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (node.isFolder) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: titleColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ] else ...[
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _subTextColor,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (time != null && time!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          time!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: titleColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              // 选中高亮 + 右侧操作区。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (trailing != null)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(child: trailing),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 文章内容预览：取去空行后的首行。
  static String _preview(String content) {
    for (final line in content.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return '';
  }
}
