import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../theme/wallpapers.dart';

/// 壁纸背景容器。
///
/// 读取当前壁纸设置并作为背景渲染（纯色 / 网络图片），
/// 子组件叠加在其上。未设置或跟随系统时使用主题默认背景。
class WallpaperBackground extends StatefulWidget {
  const WallpaperBackground({super.key, required this.child});

  final Widget child;

  @override
  State<WallpaperBackground> createState() => _WallpaperBackgroundState();
}

class _WallpaperBackgroundState extends State<WallpaperBackground> {
  WallpaperOption? _wallpaper;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsService.instance;
    if (!mounted) return;
    setState(() => _wallpaper = wallpaperByKey(s.wallpaper));
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallpaper;
    if (w == null) return widget.child;
    if (w.isColor) {
      return Container(color: w.color, child: widget.child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: CachedNetworkImageProvider(w.imageUrl!),
          fit: BoxFit.cover,
        ),
        widget.child,
      ],
    );
  }
}
