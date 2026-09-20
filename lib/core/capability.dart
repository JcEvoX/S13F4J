import 'package:flutter/material.dart';

import '../plugins/plugin_model.dart';

/// 宿主能力：插件通过 manifest 声明使用某种能力。
///
/// 逻辑由宿主实现并随应用分发，插件只做声明与配置（声明式插件模型）。
/// 新增能力 = 宿主注册一个新的 [Capability]，插件市场即可复用该能力。
abstract class Capability {
  String get id;
  String get name;
  String get description;
  IconData get icon;

  /// 从宿主 UI 打开该能力（如新建笔记、浏览文件）。
  Future<void> launch(BuildContext context, PluginManifest manifest);
}

/// 能力注册表：应用启动时注册全部可用能力。
class CapabilityRegistry {
  final Map<String, Capability> _byId = {};

  void register(Capability capability) {
    _byId[capability.id] = capability;
  }

  Capability? operator [](String id) => _byId[id];

  List<Capability> get all => _byId.values.toList();
}

/// 全局能力注册表单例。
final CapabilityRegistry capabilities = CapabilityRegistry();
