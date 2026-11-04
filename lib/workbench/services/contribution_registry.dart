import 'package:flutter/foundation.dart';

import '../base/resource_uri.dart';

/// 菜单位置 id。
class MenuIds {
  static const commandPalette = 'commandPalette';
  static const explorerContext = 'explorer/context';
  static const editorTitle = 'editor/title';
  static const viewTitle = 'view/title';
}

/// 宏命令的一步：执行另一个命令。
class CommandStep {
  const CommandStep(this.command, [this.args = const []]);

  final String command;
  final List<Object?> args;
}

class CommandContribution {
  const CommandContribution({
    required this.pluginId,
    required this.command,
    required this.title,
    this.category,
    this.when,
    this.icon,
    this.run = const [],
  });

  final String pluginId;
  final String command;
  final String title;
  final String? category;

  /// 命令可用条件（用于面板 / 菜单，不限制程序化调用）。
  final String? when;
  final String? icon;

  /// 声明式宏：没有处理函数时按顺序执行这些步骤。
  final List<CommandStep> run;

  String get label => category == null || category!.isEmpty
      ? title
      : '$category: $title';
}

class MenuContribution {
  const MenuContribution({
    required this.pluginId,
    required this.menuId,
    required this.command,
    this.when,
    this.group = '9_other',
    this.order = 0,
  });

  final String pluginId;
  final String menuId;
  final String command;
  final String? when;

  /// 分组，形如 `1_create`；按字符串升序排列，同组内按 [order]。
  final String group;
  final int order;
}

class ViewContainerContribution {
  const ViewContainerContribution({
    required this.pluginId,
    required this.id,
    required this.title,
    this.icon = 'extension',
  });

  final String pluginId;
  final String id;
  final String title;
  final String icon;
}

class ViewContribution {
  const ViewContribution({
    required this.pluginId,
    required this.id,
    required this.name,
    required this.container,
    this.when,
  });

  final String pluginId;
  final String id;
  final String name;
  final String container;
  final String? when;
}

class EditorSelector {
  const EditorSelector({this.scheme, this.filenamePattern});

  final String? scheme;
  final String? filenamePattern;

  bool matches(ResourceUri uri) {
    if (scheme != null && scheme != uri.scheme) return false;
    final pattern = filenamePattern;
    if (pattern != null && !globMatches(pattern, uri.basename)) return false;
    return true;
  }

  /// 越具体越大：scheme + 文件名模式 > 仅模式 > 仅 scheme > 无条件。
  int get specificity =>
      (scheme != null ? 1 : 0) + (filenamePattern != null ? 2 : 0);
}

enum EditorPriority { builtin, option, defaultPriority }

class EditorContribution {
  const EditorContribution({
    required this.pluginId,
    required this.viewType,
    required this.displayName,
    this.priority = EditorPriority.option,
    this.selectors = const [],
  });

  final String pluginId;
  final String viewType;
  final String displayName;
  final EditorPriority priority;
  final List<EditorSelector> selectors;

  /// 对 [uri] 的匹配得分；不匹配返回 null。
  int? scoreFor(ResourceUri uri) {
    EditorSelector? best;
    for (final selector in selectors) {
      if (!selector.matches(uri)) continue;
      if (best == null || selector.specificity > best.specificity) {
        best = selector;
      }
    }
    if (best == null) return null;
    return priority.index * 10 + best.specificity;
  }
}

class StatusBarContribution {
  const StatusBarContribution({
    required this.pluginId,
    required this.id,
    required this.text,
    this.command,
    this.tooltip,
    this.alignment = 'left',
    this.when,
  });

  final String pluginId;
  final String id;
  final String text;
  final String? command;
  final String? tooltip;
  final String alignment;
  final String? when;
}

/// 单个插件 manifest `contributes` 解析后的结果。
class PluginContributions {
  const PluginContributions({
    this.commands = const [],
    this.menus = const [],
    this.viewContainers = const [],
    this.views = const [],
    this.editors = const [],
    this.statusBar = const [],
  });

  final List<CommandContribution> commands;
  final List<MenuContribution> menus;
  final List<ViewContainerContribution> viewContainers;
  final List<ViewContribution> views;
  final List<EditorContribution> editors;
  final List<StatusBarContribution> statusBar;

  bool get isEmpty =>
      commands.isEmpty &&
      menus.isEmpty &&
      viewContainers.isEmpty &&
      views.isEmpty &&
      editors.isEmpty &&
      statusBar.isEmpty;

  /// 宽容解析：缺字段的条目被跳过，不让一个坏条目拖垮整个插件。
  factory PluginContributions.parse(
    String pluginId,
    Map<String, Object?>? json,
  ) {
    if (json == null) return const PluginContributions();
    final commands = <CommandContribution>[];
    for (final item in _maps(json['commands'])) {
      final id = item['command'];
      final title = item['title'];
      if (id is! String || id.isEmpty || title is! String) continue;
      commands.add(
        CommandContribution(
          pluginId: pluginId,
          command: id,
          title: title,
          category: item['category'] as String?,
          when: item['when'] as String?,
          icon: item['icon'] as String?,
          run: [
            for (final step in _maps(item['run']))
              if (step['command'] is String)
                CommandStep(
                  step['command']! as String,
                  (step['args'] as List?)?.cast<Object?>() ?? const [],
                ),
          ],
        ),
      );
    }

    final menus = <MenuContribution>[];
    final rawMenus = json['menus'];
    if (rawMenus is Map) {
      rawMenus.forEach((menuId, entries) {
        if (menuId is! String) return;
        for (final item in _maps(entries)) {
          final command = item['command'];
          if (command is! String || command.isEmpty) continue;
          menus.add(
            MenuContribution(
              pluginId: pluginId,
              menuId: menuId,
              command: command,
              when: item['when'] as String?,
              group: (item['group'] as String?) ?? '9_other',
              order: (item['order'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      });
    }

    final containers = <ViewContainerContribution>[];
    final rawContainers = json['viewsContainers'];
    if (rawContainers is Map) {
      for (final item in _maps(rawContainers['activitybar'])) {
        final id = item['id'];
        final title = item['title'];
        if (id is! String || title is! String) continue;
        containers.add(
          ViewContainerContribution(
            pluginId: pluginId,
            id: id,
            title: title,
            icon: (item['icon'] as String?) ?? 'extension',
          ),
        );
      }
    }

    final views = <ViewContribution>[];
    final rawViews = json['views'];
    if (rawViews is Map) {
      rawViews.forEach((container, entries) {
        if (container is! String) return;
        for (final item in _maps(entries)) {
          final id = item['id'];
          final name = item['name'];
          if (id is! String || name is! String) continue;
          views.add(
            ViewContribution(
              pluginId: pluginId,
              id: id,
              name: name,
              container: container,
              when: item['when'] as String?,
            ),
          );
        }
      });
    }

    final editors = <EditorContribution>[];
    for (final item in _maps(json['editors'])) {
      final viewType = item['viewType'];
      if (viewType is! String || viewType.isEmpty) continue;
      editors.add(
        EditorContribution(
          pluginId: pluginId,
          viewType: viewType,
          displayName: (item['displayName'] as String?) ?? viewType,
          priority: item['priority'] == 'default'
              ? EditorPriority.defaultPriority
              : item['priority'] == 'builtin'
                  ? EditorPriority.builtin
                  : EditorPriority.option,
          selectors: [
            for (final selector in _maps(item['selector']))
              EditorSelector(
                scheme: selector['scheme'] as String?,
                filenamePattern: selector['filenamePattern'] as String?,
              ),
          ],
        ),
      );
    }

    final statusBar = <StatusBarContribution>[];
    for (final item in _maps(json['statusBar'])) {
      final id = item['id'];
      final text = item['text'];
      if (id is! String || text is! String) continue;
      statusBar.add(
        StatusBarContribution(
          pluginId: pluginId,
          id: id,
          text: text,
          command: item['command'] as String?,
          tooltip: item['tooltip'] as String?,
          alignment: item['alignment'] == 'right' ? 'right' : 'left',
          when: item['when'] as String?,
        ),
      );
    }

    return PluginContributions(
      commands: commands,
      menus: menus,
      viewContainers: containers,
      views: views,
      editors: editors,
      statusBar: statusBar,
    );
  }

  static Iterable<Map<String, Object?>> _maps(Object? value) sync* {
    if (value is! List) return;
    for (final item in value) {
      if (item is Map) yield item.cast<String, Object?>();
    }
  }
}

/// 全部插件贡献的汇总。插件启停时整体替换 / 移除该插件的贡献。
class ContributionRegistry extends ChangeNotifier {
  final Map<String, PluginContributions> _byPlugin = {};

  Iterable<String> get pluginIds => _byPlugin.keys;

  void setPlugin(String pluginId, PluginContributions contributions) {
    _byPlugin[pluginId] = contributions;
    notifyListeners();
  }

  void removePlugin(String pluginId) {
    if (_byPlugin.remove(pluginId) != null) notifyListeners();
  }

  Iterable<PluginContributions> get _all => _byPlugin.values;

  List<CommandContribution> get commands =>
      [for (final c in _all) ...c.commands];

  CommandContribution? command(String id) {
    for (final c in _all) {
      for (final command in c.commands) {
        if (command.command == id) return command;
      }
    }
    return null;
  }

  /// 某菜单位置的条目，按 group、order 排序；无对应命令声明的条目被丢弃。
  List<MenuContribution> menu(String menuId) {
    final items = [
      for (final c in _all)
        for (final m in c.menus)
          if (m.menuId == menuId && command(m.command) != null) m,
    ];
    items.sort((a, b) {
      final g = a.group.compareTo(b.group);
      return g != 0 ? g : a.order.compareTo(b.order);
    });
    return items;
  }

  List<ViewContainerContribution> get viewContainers =>
      [for (final c in _all) ...c.viewContainers];

  List<ViewContribution> viewsOf(String containerId) => [
        for (final c in _all)
          for (final v in c.views)
            if (v.container == containerId) v,
      ];

  List<EditorContribution> get editors => [for (final c in _all) ...c.editors];

  List<StatusBarContribution> get statusBarItems =>
      [for (final c in _all) ...c.statusBar];
}

/// 文件名通配：`*` `?` `{a,b}`，大小写不敏感，匹配整个文件名。
bool globMatches(String pattern, String name) =>
    _globToRegExp(pattern).hasMatch(name);

final Map<String, RegExp> _globCache = {};

RegExp _globToRegExp(String pattern) =>
    _globCache.putIfAbsent(pattern, () {
      final buffer = StringBuffer('^');
      var inGroup = false;
      for (final rune in pattern.runes) {
        final c = String.fromCharCode(rune);
        switch (c) {
          case '*':
            buffer.write('.*');
          case '?':
            buffer.write('.');
          case '{':
            inGroup = true;
            buffer.write('(?:');
          case '}':
            inGroup = false;
            buffer.write(')');
          case ',':
            buffer.write(inGroup ? '|' : ',');
          default:
            buffer.write(RegExp.escape(c));
        }
      }
      buffer.write(r'$');
      return RegExp(buffer.toString(), caseSensitive: false);
    });
