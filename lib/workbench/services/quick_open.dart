import 'dart:async';

import '../base/fuzzy.dart';
import '../base/resource_uri.dart';
import 'contribution_registry.dart';
import 'file_system.dart';
import 'workbench.dart';

/// 命令面板中的一条文件结果。
class FileMatch {
  const FileMatch(this.uri, this.score);

  final ResourceUri uri;
  final int score;
}

class CommandMatch {
  const CommandMatch(this.command, this.score);

  final CommandContribution command;
  final int score;
}

/// 快速打开：文件名模糊匹配（跨全部工作区文件夹）与命令搜索。
class QuickOpenService {
  QuickOpenService(this.workbench) {
    _subscription = workbench.fileSystems.onDidChange.listen((dir) {
      _index.remove(dir.scheme);
    });
  }

  final Workbench workbench;

  /// 每个 scheme 最多索引的文件数 / 目录深度，防止超大目录拖慢面板。
  static const int maxFilesPerFolder = 5000;
  static const int maxDepth = 10;

  final Map<String, Future<List<ResourceUri>>> _index = {};
  late final StreamSubscription<ResourceUri> _subscription;

  void invalidate([String? scheme]) {
    if (scheme == null) {
      _index.clear();
    } else {
      _index.remove(scheme);
    }
  }

  Future<List<ResourceUri>> _filesOf(WorkspaceFolder folder) =>
      _index.putIfAbsent(folder.scheme, () => _walk(folder));

  Future<List<ResourceUri>> _walk(WorkspaceFolder folder) async {
    final files = <ResourceUri>[];
    final queue = <(ResourceUri, int)>[(folder.root, 0)];
    while (queue.isNotEmpty && files.length < maxFilesPerFolder) {
      final (dir, depth) = queue.removeAt(0);
      List<DirEntry> entries;
      try {
        entries = await workbench.fileSystems.readDirectory(dir);
      } catch (_) {
        continue;
      }
      for (final entry in entries) {
        final child = dir.join(entry.name);
        if (entry.isDirectory) {
          if (depth + 1 <= maxDepth) queue.add((child, depth + 1));
        } else {
          files.add(child);
          if (files.length >= maxFilesPerFolder) break;
        }
      }
    }
    return files;
  }

  /// 文件名匹配；空查询返回最近打开的文件。
  Future<List<FileMatch>> findFiles(String query, {int limit = 50}) async {
    final text = query.trim();
    if (text.isEmpty) {
      return [
        for (final uri in workbench.recentResources.take(limit))
          FileMatch(uri, 0),
      ];
    }
    final matches = <FileMatch>[];
    for (final folder in workbench.activeFolders) {
      final files = await _filesOf(folder);
      for (final uri in files) {
        // 文件名命中优先于路径命中。
        final nameScore = fuzzyScore(text, uri.basename);
        final pathScore = fuzzyScore(text, '${uri.scheme}${uri.path}');
        if (nameScore == null && pathScore == null) continue;
        final score = nameScore != null ? nameScore + 20 : pathScore!;
        matches.add(FileMatch(uri, score));
      }
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.uri.path.compareTo(b.uri.path);
    });
    return matches.take(limit).toList();
  }

  /// 命令搜索；空查询按声明顺序返回全部可用命令。
  List<CommandMatch> findCommands(String query, {int limit = 100}) {
    final text = query.trim();
    final commands = workbench.paletteCommands();
    if (text.isEmpty) {
      return [for (final c in commands.take(limit)) CommandMatch(c, 0)];
    }
    final matches = <CommandMatch>[];
    for (final command in commands) {
      final score = fuzzyScore(text, command.label);
      if (score != null) matches.add(CommandMatch(command, score));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(limit).toList();
  }

  void dispose() {
    _subscription.cancel();
  }
}
