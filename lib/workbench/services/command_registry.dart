import 'dart:async';

import 'package:flutter/foundation.dart';

import '../base/disposable.dart';
import 'workbench.dart';

/// 命令执行上下文。
class CommandContext {
  const CommandContext({required this.workbench, this.args = const []});

  final Workbench workbench;
  final List<Object?> args;

  /// 取第 [index] 个参数并转成目标类型；缺失或类型不符返回 null。
  T? arg<T>(int index) {
    if (index >= args.length) return null;
    final value = args[index];
    return value is T ? value : null;
  }
}

typedef CommandHandler = FutureOr<Object?> Function(CommandContext context);

/// 命令找不到或没有实现。
class CommandNotFoundError implements Exception {
  const CommandNotFoundError(this.id, {this.declared = false});

  final String id;

  /// 已在 manifest 声明，但没有对应实现。
  final bool declared;

  @override
  String toString() => declared
      ? '命令 "$id" 已声明但尚未实现（能力未提供处理函数）'
      : '未知命令: $id';
}

/// 命令处理函数注册表。元数据（标题 / 分类 / when）在 ContributionRegistry。
class CommandRegistry extends ChangeNotifier {
  final Map<String, CommandHandler> _handlers = {};

  Iterable<String> get ids => _handlers.keys;

  bool hasHandler(String id) => _handlers.containsKey(id);

  CommandHandler? handlerOf(String id) => _handlers[id];

  Disposable register(String id, CommandHandler handler) {
    if (_handlers.containsKey(id)) {
      throw StateError('命令已注册: $id');
    }
    _handlers[id] = handler;
    notifyListeners();
    return toDisposable(() {
      if (_handlers[id] == handler) {
        _handlers.remove(id);
        notifyListeners();
      }
    });
  }
}
