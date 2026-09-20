import 'dart:ui';

/// 壁纸选项。
///
/// 对应原 Android 端 WallpaperUI 的壁纸列表：
/// 纯色壁纸（跟随系统 / 默认白 / 默认黑 / 原木 / 纯白 / 纯黑）
/// 与网络图片壁纸（浆纸 / 牛皮纸 / 斑驳 / 大理石 / 云霭 / 沙滩 / 层峦）。
class WallpaperOption {
  const WallpaperOption({
    required this.key,
    required this.title,
    this.subtitle,
    this.colorValue,
    this.imageUrl,
    this.isDark = false,
  });

  /// 存储键（写入设置）。
  final String key;

  /// 显示名称。
  final String title;

  /// 副标题说明。
  final String? subtitle;

  /// 纯色壁纸（ARGB 值）。
  final int? colorValue;

  /// 网络图片壁纸地址。
  final String? imageUrl;

  /// 是否为深色壁纸（决定前景文字颜色）。
  final bool isDark;

  bool get isColor => imageUrl == null;

  Color? get color => colorValue == null ? null : Color(colorValue!);

  /// 选中当前壁纸时的默认选中样式。
  bool get isFollowSystem => key == 'DayNight';
}

/// 全部壁纸（顺序与原 Android 端一致）。
const List<WallpaperOption> kWallpapers = [
  WallpaperOption(
    key: 'DayNight',
    title: '跟随系统',
    subtitle: 'DayNight',
    colorValue: 0xFFF5F6F8,
  ),
  WallpaperOption(
    key: 'Day',
    title: '默认白',
    subtitle: 'Day',
    colorValue: 0xFFF5F6F8,
  ),
  WallpaperOption(
    key: 'Night',
    title: '默认黑',
    subtitle: 'Night',
    colorValue: 0xFF141414,
    isDark: true,
  ),
  WallpaperOption(
    key: 'wood',
    title: '原木',
    subtitle: '朴实无华',
    colorValue: 0xFFFFF5E4,
  ),
  WallpaperOption(
    key: 'paper',
    title: '浆纸',
    subtitle: '磨砂质感，经典之作',
    imageUrl:
        'https://images.unsplash.com/photo-1604147706283-d7119b5b822c?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'kraft',
    title: '牛皮纸',
    subtitle: '平整光滑，复古自然',
    imageUrl:
        'https://images.unsplash.com/photo-1615800098799-0ccb261b1f92?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'mottled',
    title: '斑驳',
    subtitle: '时光婆娑，岁月斑驳',
    imageUrl:
        'https://images.unsplash.com/photo-1555181937-efe4e074a301?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'marble',
    title: '大理石',
    subtitle: '被禁锢的天使',
    imageUrl:
        'https://images.unsplash.com/photo-1566305977571-5666677c6e98?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'cloud',
    title: '云霭',
    subtitle: '如坠云霄之中',
    imageUrl:
        'https://images.unsplash.com/photo-1612178537253-bccd437b730e?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'beach',
    title: '沙滩',
    subtitle: '玫瑰色的海岸',
    imageUrl:
        'https://images.unsplash.com/photo-1612293025896-7200cc87e540?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'mountain',
    title: '层峦',
    subtitle: '画阁层峦，雨余烟簇',
    imageUrl:
        'https://images.unsplash.com/photo-1551376347-075b0121a65b?auto=format&fit=crop&w=800&q=60',
  ),
  WallpaperOption(
    key: 'white',
    title: '纯白',
    subtitle: 'WHITE',
    colorValue: 0xFFFFFFFF,
  ),
  WallpaperOption(
    key: 'oled',
    title: '纯黑',
    subtitle: 'OLED',
    colorValue: 0xFF000000,
    isDark: true,
  ),
];

/// 根据存储键查找壁纸；未找到或为 DayNight 返回 null（跟随系统）。
WallpaperOption? wallpaperByKey(String? key) {
  if (key == null || key.isEmpty || key == 'DayNight') return null;
  for (final w in kWallpapers) {
    if (w.key == key) return w;
  }
  return null;
}
