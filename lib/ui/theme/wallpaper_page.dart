import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../theme/wallpapers.dart';

/// 壁纸选择页。
///
/// 对应原 Android 端的「壁纸」，双列网格展示纯色与图片壁纸，
/// 选中后写入设置并应用到首页 / 编辑器背景。
class WallpaperPage extends StatefulWidget {
  const WallpaperPage({super.key});

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsService.instance;
    if (!mounted) return;
    setState(() => _settings = s);
  }

  Future<void> _apply(WallpaperOption w) async {
    final s = _settings!;
    // DayNight 表示跟随系统（清除设置）。
    await s.setWallpaper(w.isFollowSystem ? null : w.key);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('壁纸')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              itemCount: kWallpapers.length,
              itemBuilder: (ctx, i) => _buildItem(ctx, s, kWallpapers[i]),
            ),
    );
  }

  Widget _buildItem(BuildContext context, SettingsService s, WallpaperOption w) {
    final selected = (s.wallpaper == null && w.isFollowSystem) ||
        s.wallpaper == w.key;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _apply(w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black12,
                  width: selected ? 3 : 1,
                ),
                image: w.isColor
                    ? null
                    : DecorationImage(
                        image: CachedNetworkImageProvider(w.imageUrl!),
                        fit: BoxFit.cover,
                      ),
                color: w.isColor ? w.color : null,
              ),
              child: selected
                  ? Center(
                      child: Icon(
                        Icons.check_circle,
                        color: w.isDark ? Colors.white : Colors.black54,
                        size: 32,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            w.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (w.subtitle != null)
            Text(
              w.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }
}
