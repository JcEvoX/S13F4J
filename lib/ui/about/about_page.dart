import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于页：版本信息与对原作者 Moriafly 的致谢。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final ValueNotifier<String> _version = ValueNotifier('');

  static const _originalAuthor = 'Moriafly';
  static const _originalRepo = 'https://github.com/Moriafly/SaltNoteSource';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _version.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    _version.value = '${info.version}(${info.buildNumber})';
  }

  Future<void> _launch(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Icon(Icons.restaurant_menu,
                size: 72, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('NotePad',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<String>(
            valueListenable: _version,
            builder: (_, v, __) => Center(
              child: Text(
                v.isEmpty ? '版本 读取中…' : '版本 $v',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const _SectionTitle('🙏 致谢原作者'),
          const SizedBox(height: 8),
          Text(
            '本项目的功能设计与交互参照了原 Android 开源项目'
            '「椒盐笔记 (Salt Note)」。特别感谢原作者：',
            style: TextStyle(height: 1.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: const Text(_originalAuthor),
              subtitle: const Text('GitHub: @$_originalAuthor'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launch(context, 'https://github.com/Moriafly'),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: const Text('原项目仓库'),
            subtitle: const Text(_originalRepo),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launch(context, _originalRepo),
          ),
          const SizedBox(height: 8),
          Text(
            '作者旗下其它开源项目：椒盐音乐 (SaltPlayerSource)、'
            'DsoMusic、LyricViewX、Regret 等。',
            style: TextStyle(height: 1.5, color: Colors.grey.shade700, fontSize: 13),
          ),
          const Divider(),
          const _SectionTitle('声明'),
          const SizedBox(height: 8),
          Text(
            '本项目为基于原项目功能描述，用 Flutter 重新实现的跨平台学习项目，'
            '原项目部分能力需要购买 Pro，本项目的功能与授权均以原项目为准。',
            style: TextStyle(height: 1.6, color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}