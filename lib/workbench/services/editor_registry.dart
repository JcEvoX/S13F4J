import 'package:flutter/widgets.dart';

import '../base/disposable.dart';
import '../base/resource_uri.dart';
import 'contribution_registry.dart';

/// 宿主内置：通用文本编辑器 / 欢迎页。
const String kTextEditorViewType = 'workbench.text';
const String kWelcomeViewType = 'workbench.welcome';

/// 一个打开的编辑器实例（对应一个标签）。
class EditorInput {
  EditorInput({
    required this.id,
    required this.viewType,
    required String title,
    this.resource,
  }) : title = ValueNotifier<String>(title);

  final String id;
  final String viewType;

  /// 无资源的编辑器（欢迎页等）为 null。
  final ResourceUri? resource;

  /// 标签标题；编辑器可在加载后更新。
  final ValueNotifier<String> title;

  /// 有未保存内容。标签显示圆点，关闭前由编辑器负责落盘。
  final ValueNotifier<bool> dirty = ValueNotifier<bool>(false);

  void dispose() {
    title.dispose();
    dirty.dispose();
  }
}

typedef EditorBuilder = Widget Function(BuildContext context, EditorInput input);

/// 编辑器 provider 注册表 + 按资源解析编辑器。
class EditorRegistry extends ChangeNotifier {
  EditorRegistry(this._contributions);

  final ContributionRegistry _contributions;
  final Map<String, EditorBuilder> _builders = {};

  Disposable register(String viewType, EditorBuilder builder) {
    if (_builders.containsKey(viewType)) {
      throw StateError('编辑器已注册: $viewType');
    }
    _builders[viewType] = builder;
    notifyListeners();
    return toDisposable(() {
      if (_builders[viewType] == builder) {
        _builders.remove(viewType);
        notifyListeners();
      }
    });
  }

  EditorBuilder? builderFor(String viewType) => _builders[viewType];

  bool hasProvider(String viewType) => _builders.containsKey(viewType);

  /// 能打开 [uri] 的编辑器声明，得分高者在前。
  List<EditorContribution> candidates(ResourceUri uri) {
    final scored = <(EditorContribution, int)>[];
    for (final editor in _contributions.editors) {
      final score = editor.scoreFor(uri);
      if (score != null) scored.add((editor, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final item in scored) item.$1];
  }

  String displayNameOf(String viewType) {
    for (final editor in _contributions.editors) {
      if (editor.viewType == viewType) return editor.displayName;
    }
    return viewType;
  }

  /// 默认编辑器：优先 `default` 优先级的候选，其次内置，最后通用文本编辑器。
  String resolve(ResourceUri uri) {
    final list = candidates(uri);
    for (final editor in list) {
      if (editor.priority == EditorPriority.defaultPriority) {
        return editor.viewType;
      }
    }
    for (final editor in list) {
      if (editor.priority == EditorPriority.builtin) return editor.viewType;
    }
    return kTextEditorViewType;
  }
}
