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
    final stat = await NoteDao().statistics();
    if (!mounted) return;
    setState(() => _stat = stat);
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
      color: scheme.primaryContainer.withOpacity(0.35),
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
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
