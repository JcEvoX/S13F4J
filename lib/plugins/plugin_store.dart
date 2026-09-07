import 'dart:convert';

import 'package:http/http.dart' as http;

/// 插件市场条目（来自插件仓库 Release 的插件安装包）。
class MarketPlugin {
  const MarketPlugin({
    required this.name,
    required this.version,
    required this.downloadUrl,
    required this.releaseName,
    required this.size,
  });

  /// 安装包文件名，如 `notes-plugin-1.0.0.zip`。
  final String name;
  final String version;
  final String downloadUrl;
  final String releaseName;
  final int size;
}

/// 插件市场：从 GitHub 插件仓库拉取并下载插件安装包。
///
/// 分发约定：插件仓库的 Release assets 中以 `.zip` 结尾的即插件安装包
/// （内含 plugin.json + 可选资源）。软件本体（APK/IPA）由主仓库发布，
/// 插件独立仓库只负责插件分发。
class PluginStore {
  PluginStore._();

  /// 默认插件源：独立插件仓库。
  static const defaultSource = 'JcEvoX/S13F4J-plugins';

  /// 拉取插件仓库最近 releases 中的所有 `*.zip` 插件包。
  static Future<List<MarketPlugin>> fetchMarket(String repo) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/releases?per_page=10',
    );
    final resp = await http.get(
      uri,
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (resp.statusCode != 200) {
      throw Exception('插件源拉取失败（HTTP ${resp.statusCode}）');
    }
    final releases = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
    final result = <MarketPlugin>[];
    for (final release in releases.cast<Map<String, dynamic>>()) {
      final tag = release['tag_name'] as String? ?? '';
      final releaseName = release['name'] as String? ?? tag;
      final assets = (release['assets'] as List?) ?? const [];
      for (final asset in assets.cast<Map<String, dynamic>>()) {
        final assetName = asset['name'] as String? ?? '';
        if (!assetName.toLowerCase().endsWith('.zip')) continue;
        result.add(
          MarketPlugin(
            name: assetName,
            version: tag,
            downloadUrl: asset['browser_download_url'] as String? ?? '',
            releaseName: releaseName,
            size: (asset['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    return result;
  }

  /// 下载插件安装包字节。
  static Future<List<int>> download(Uri url) async {
    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      throw Exception('插件下载失败（HTTP ${resp.statusCode}）');
    }
    return resp.bodyBytes;
  }
}
