# 椒盐笔记 · Flutter 跨平台版（Salt Note for Flutter）

> 一款纯文本 + Markdown 的跨平台笔记软件，可用于便签、日记、文稿撰写。
> 本仓库是基于原 Android 版「椒盐笔记」**用 Flutter 重新实现**的
> **Android / iOS / 桌面（预研）** 三端工程，按功能模块增量演进。

## ✨ 功能

- **高自由度的文章管理**
  - 无限嵌套的多层级文件夹
  - 任意拖拽排序（重启后仍生效）
  - 随意多选并移动到其他文件夹
- **优秀的 Markdown 编辑**
  - Markdown 标记文本，语法实时高亮
  - 工具栏快捷插入 Markdown 符号
- **强大的 Markdown 渲染**
  - 覆盖常见 Markdown 元素、代码高亮、数学公式、Mermaid 图表、HTML
  - 本地图片 / 网络图片缓存支持
- **全面的导出**
  - 导出为图片、纯文本（.txt）、Markdown（.md）、PDF（.pdf）
- **完善的文章保护**
  - 编辑实时保存、后台自动备份、回收站防误删
- **用户体验与个性化**
  - 软件内数据库保存 + 本地文件夹备份 + WebDAV 备份
  - 沉浸式创作，无打扰通知
  - 内置精选壁纸、本地相册自定义壁纸、自定义编辑器字体与字号
  - 实时字数统计、撤销 / 重做
  - 深色模式：跟随系统 / 浅色 / 深色

## 📱 平台支持

| 平台 | 状态 |
| ---- | ---- |
| Android | ✅ 支持 |
| iOS | ✅ 支持 |
| Linux / Windows / macOS | 🚧 桌面端预研（FFI 数据层与文件选择已按跨端预留） |

## 🏗️ 工程结构（对应原功能模块）

```
lib/
├─ data/          # 数据库层（多层级节点、回收站、搜索）
├─ models/        # 数据模型
├─ services/      # 设置、导出、WebDAV 等服务
├─ theme/         # 主题与配色
├─ ui/
│  ├─ home/       # 首页：文件管理器式多层级列表 + 拖拽排序
│  ├─ editor/     # Markdown 编辑器
│  ├─ preview/    # Markdown 预览渲染
│  ├─ recyclebin/ # 回收站
│  ├─ search/     # 关键词搜索
│  ├─ webdav/     # WebDAV 备份
│  ├─ settings/   # 设置
│  └─ about/      # 关于
└─ widgets/       # 通用组件
```

## 🧭 开发与构建

```bash
# 依赖安装
flutter pub get

# Android / iOS
flutter run -d <device>

# 桌面（需要开启对应平台 toolchain）
flutter create . --platforms=linux,windows,macos
flutter run -d linux
```

> Windows / macOS 桌面运行需在已启用该平台工具链的本机执行 `flutter config --enable-*`。

## 🙏 致谢

本项目为非商业的开源学习项目，**代码为 Flutter 重新实现**，功能设计与交互参照了
原 Android 开源项目 **椒盐笔记 (Salt Note)**：

- **原作者：Moriafly**（[GitHub @Moriafly](https://github.com/Moriafly)）
- 原仓库：[Moriafly/SaltNoteSource](https://github.com/Moriafly/SaltNoteSource)
- 作者旗下其他项目：椒盐音乐 [Moriafly/SaltPlayerSource](https://github.com/Moriafly/SaltPlayerSource) 等

> 本仓库仅保留对原作者的致敬与功能参考，未包含原 Android 闭源代码。
> 原项目部分能力需要购买 Pro，本项目为纯学习演示实现，能力与授权均以原项目为准。

## 📄 许可

本项目使用 MIT License，详情见 `LICENSE`。