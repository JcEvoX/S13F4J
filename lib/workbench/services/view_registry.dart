import 'package:flutter/widgets.dart';

import '../base/disposable.dart';
import 'workbench.dart';

typedef ViewBuilder = Widget Function(BuildContext context, Workbench workbench);

/// 视图内容注册表：manifest 声明视图（`views`），实现由能力在激活时注册。
class ViewRegistry extends ChangeNotifier {
  final Map<String, ViewBuilder> _builders = {};

  Disposable register(String viewId, ViewBuilder builder) {
    if (_builders.containsKey(viewId)) {
      throw StateError('视图已注册: $viewId');
    }
    _builders[viewId] = builder;
    notifyListeners();
    return toDisposable(() {
      if (_builders[viewId] == builder) {
        _builders.remove(viewId);
        notifyListeners();
      }
    });
  }

  ViewBuilder? builderFor(String viewId) => _builders[viewId];
}
