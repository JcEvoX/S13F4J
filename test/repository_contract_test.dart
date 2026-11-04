import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/app_database.dart';
import 'package:notepad/data/notes_repository.dart';
import 'package:notepad/data/sqlite_notes_repository.dart';
import 'package:notepad/data/vault/vault_notes_repository.dart';
import 'package:notepad/models/note.dart';

/// 同一套契约同时约束 sqlite（过渡实现）与文件实现（vault），
/// 保证 backend 开关切换前后的可见行为一致（D10 / M0 验收）。
class _Backend {
  const _Backend(this.name, this.open);

  final String name;
  final Future<NotesRepository> Function(Directory root) open;
}

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final backends = <_Backend>[
    _Backend('sqlite', (root) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        return root.path;
      });
      final repo = SqliteNotesRepository();
      await repo.init();
      return repo;
    }),
    _Backend('vault', (root) async {
      final repo = VaultNotesRepository.atRoot(root.path);
      await repo.init();
      return repo;
    }),
  ];

  for (final backend in backends) {
    group('NotesRepository 契约 · ${backend.name}', () {
      late Directory tempDir;
      late NotesRepository repo;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('notepad_contract_');
        repo = await backend.open(tempDir);
      });

      tearDown(() async {
        await repo.close();
        await AppDatabase.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_pathProviderChannel, null);
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      Future<List<String>> titles(String? folderId) async =>
          (await repo.childrenOf(folderId)).map((n) => n.title).toList();

      test('空库没有用户内容', () async {
        expect(await repo.hasUserContent(), isFalse);
        expect(await repo.childrenOf(null), isEmpty);
        expect(await repo.nodeById('missing'), isNull);
      });

      test('新建 / 读写正文，id 在改名后保持稳定', () async {
        final note = await repo.createNode(
          isFolder: false,
          title: 'Hello',
          content: 'first',
        );
        expect(await repo.hasUserContent(), isTrue);
        expect(await repo.readBody(note.id), 'first');

        await repo.writeBody(note.id, 'second');
        expect(await repo.readBody(note.id), 'second');

        await repo.rename(note.id, 'World');
        final renamed = await repo.nodeById(note.id);
        expect(renamed, isNotNull);
        expect(renamed!.title, 'World');
        expect(await repo.readBody(note.id), 'second');
        expect(await titles(null), ['World']);
      });

      test('读取不存在的节点抛出 E-NOT-FOUND', () async {
        await expectLater(
          repo.readBody('missing'),
          throwsA(
            isA<NotesException>().having((e) => e.code, 'code', 'E-NOT-FOUND'),
          ),
        );
      });

      test('层级：子节点只出现在自己的父级下', () async {
        final folder = await repo.createNode(isFolder: true, title: 'Work');
        await repo.createNode(
          isFolder: false,
          title: 'Plan',
          parentId: folder.id,
        );
        await repo.createNode(isFolder: false, title: 'Top');

        expect(await titles(null), unorderedEquals(['Work', 'Top']));
        expect(await titles(folder.id), ['Plan']);
        expect(
          (await repo.allFolders()).map((n) => n.title),
          contains('Work'),
        );
      });

      test('同层排序持久化', () async {
        final a = await repo.createNode(isFolder: false, title: 'A');
        final b = await repo.createNode(isFolder: false, title: 'B');
        final c = await repo.createNode(isFolder: false, title: 'C');

        await repo.reorder(null, [c.id, a.id, b.id]);
        expect(await titles(null), ['C', 'A', 'B']);
      });

      test('排序包含非本层节点时拒绝', () async {
        final a = await repo.createNode(isFolder: false, title: 'A');
        await expectLater(
          repo.reorder(null, [a.id, 'not-here']),
          throwsA(isA<NotesException>()),
        );
      });

      test('移动到文件夹', () async {
        final folder = await repo.createNode(isFolder: true, title: 'Box');
        final note = await repo.createNode(isFolder: false, title: 'Item');

        await repo.move([note.id], folder.id);
        expect(await titles(folder.id), ['Item']);
        expect(await titles(null), ['Box']);

        await repo.move([note.id], null);
        expect(await titles(folder.id), isEmpty);
        expect(await titles(null), unorderedEquals(['Box', 'Item']));
      });

      test('文件夹不能移动到自身或后代', () async {
        final parent = await repo.createNode(isFolder: true, title: 'P');
        final child = await repo.createNode(
          isFolder: true,
          title: 'C',
          parentId: parent.id,
        );

        await expectLater(
          repo.move([parent.id], parent.id),
          throwsA(isA<NotesException>()),
        );
        await expectLater(
          repo.move([parent.id], child.id),
          throwsA(isA<NotesException>()),
        );
      });

      test('回收站：整棵子树进出，永久删除不可恢复', () async {
        final folder = await repo.createNode(isFolder: true, title: 'Docs');
        await repo.createNode(
          isFolder: false,
          title: 'Readme',
          parentId: folder.id,
          content: 'body',
        );
        final temp = await repo.createNode(isFolder: false, title: 'Temp');

        await repo.moveToTrash([folder.id]);
        final trashed = await repo.listTrash();
        expect(trashed.map((e) => e.entry.id), [folder.id]);
        expect(trashed.single.entry.isFolder, isTrue);
        expect(await titles(null), ['Temp']);

        await repo.restore([folder.id]);
        expect(await titles(null), unorderedEquals(['Docs', 'Temp']));
        expect(await titles(folder.id), ['Readme']);
        expect(await repo.listTrash(), isEmpty);

        await repo.moveToTrash([temp.id]);
        expect(await repo.listTrash(), hasLength(1));
        await repo.purge([temp.id]);
        expect(await repo.listTrash(), isEmpty);
        expect(await titles(null), ['Docs']);
      });

      test('搜索匹配标题与正文，空关键字无结果', () async {
        await repo.createNode(
          isFolder: false,
          title: 'Plan',
          content: 'alpha 项目',
        );
        await repo.createNode(isFolder: false, title: 'Ideas', content: 'beta');

        expect(
          (await repo.search('alpha')).map((n) => n.title).toList(),
          ['Plan'],
        );
        expect(
          (await repo.search('ideas')).map((n) => n.title).toList(),
          ['Ideas'],
        );
        expect(await repo.search(''), isEmpty);
      });

      test('最近编辑只含文章；统计与回收站一致', () async {
        final folder = await repo.createNode(isFolder: true, title: 'F');
        await repo.createNode(
          isFolder: false,
          title: 'N1',
          parentId: folder.id,
          content: 'one two',
        );
        final n2 = await repo.createNode(isFolder: false, title: 'N2');

        final recent = await repo.recent();
        expect(recent.any((n) => n.isFolder), isFalse);
        expect(recent.map((n) => n.title), unorderedEquals(['N1', 'N2']));

        await repo.moveToTrash([n2.id]);
        final stats = await repo.statistics();
        expect(stats.folders, 1);
        expect(stats.articles, 1);
        expect(stats.recycled, 1);
      });

      test('replaceAll 用给定节点整体替换，allNodes 往返一致', () async {
        await repo.createNode(isFolder: false, title: 'Old', content: 'old');

        final now = DateTime.now().millisecondsSinceEpoch;
        NotePadNode node(
          String id,
          String title, {
          bool isFolder = false,
          String? parentId,
          String content = '',
        }) =>
            NotePadNode(
              id: id,
              isFolder: isFolder,
              title: title,
              content: content,
              parentId: parentId,
              sortOrder: 0,
              isRecycled: false,
              createdAt: now,
              updatedAt: now,
            );

        await repo.replaceAll([
          node('f1', 'Folder', isFolder: true),
          node('n1', 'Inside', parentId: 'f1', content: 'text'),
          node('n2', 'Root', content: 'root body'),
        ]);

        expect(await titles(null), unorderedEquals(['Folder', 'Root']));
        expect(await titles('f1'), ['Inside']);
        expect(await repo.readBody('n1'), 'text');
        expect((await repo.allNodes()).length, 3);
      });
    });
  }
}
