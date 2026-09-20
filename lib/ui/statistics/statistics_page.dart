import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/note_dao.dart';

/// 统计页。
///
/// 对应原 Android 端的「统计」入口，展示文章数量、文件夹数量、
/// 总字数、回收站数量与最近编辑时间等维度。
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  NoteStatistics? _stat;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    debugPrint('[Statistics] 加载统计');
    final stat = await NoteDao().statistics();
    if (!mounted) return;
    setState(() => _stat = stat);
    debugPrint('[Statistics] 加载完成: 文章=${stat.articles}, 文件夹=${stat.folders}, 字数=${stat.words}, 回收站=${stat.recycled}');
  }

  @override
  Widget build(BuildContext context) {
    final stat = _stat;
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: stat == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCard(stat),
                const SizedBox(height: 16),
                _tile(
                  icon: Icons.article_outlined,
                  label: '文章数量',
                  value: '${stat.articles}',
                ),
                _tile(
                  icon: Icons.folder_outlined,
                  label: '文件夹数量',
                  value: '${stat.folders}',
                ),
                _tile(
                  icon: Icons.numbers,
                  label: '总字数',
                  value: _formatCount(stat.words),
                ),
                _tile(
                  icon: Icons.delete_outline,
                  label: '回收站节点',
                  value: '${stat.recycled}',
                ),
                _tile(
                  icon: Icons.schedule,
                  label: '最近编辑时间',
                  value: stat.lastEditedAt == 0
                      ? '暂无'
                      : DateFormat('yyyy-MM-dd HH:mm')
                          .format(DateTime.fromMillisecondsSinceEpoch(
                              stat.lastEditedAt)),
                ),
              ],
            ),
    );
  }

  Widget _summaryCard(NoteStatistics stat) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _statBlock(scheme, '文章', '${stat.articles}'),
            ),
            Container(
              width: 1,
              height: 40,
              color: scheme.outlineVariant,
            ),
            Expanded(
              child: _statBlock(scheme, '字数', _formatCount(stat.words)),
            ),
            Container(
              width: 1,
              height: 40,
              color: scheme.outlineVariant,
            ),
            Expanded(
              child: _statBlock(scheme, '文件夹', '${stat.folders}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBlock(ColorScheme scheme, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final dim = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.grey.shade600;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: dim.withValues(alpha: 0.16), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: scheme.onSurface),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(1)} 万';
    }
    return '$n';
  }
}
