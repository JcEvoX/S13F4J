import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/notes_repository.dart';
import 'package:notepad/data/vault/vault_notes_repository.dart';
import 'package:notepad/models/note.dart';
import 'package:path/path.dart' as p;

NotePadNode _node({
  required String id,
  required bool isFolder,
  required String title,
  String content = '',
  String? parentId,
  int sortOrder = 0,
  int createdAt = 1000,
  int updatedAt = 2000,
  bool isRecycled = false,
  int? deletedAt,
}) {
  return NotePadNode(
    id: id,
    isFolder: isFolder,
    title: title,
    content: content,
    parentId: parentId,
    sortOrder: sortOrder,
    isRecycled: isRecycled,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

void main() {
  late Directory tempDir;
  late VaultNotesRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notepad_vault_test_');
    repo = VaultNotesRepository.atRoot(tempDir.path);
    await repo.init();
  });

  tearDown(() async {
    await repo.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String abs(String rel) => p.join(tempDir.path, rel);

  test('初始化建立布局，无内容时不视为已有用户数据', () async {
    expect(Directory(abs('.notepad')).existsSync(), isTrue);
    expect(Directory(abs('.notepad/trash/items')).existsSync(), isTrue);
    expect(File(abs('.notepad/namespace.json')).existsSync(), isTrue);
    expect(await repo.hasUserContent(), isFalse);
  });

  test('外部新增的文件与文件夹启动时自动对账', () async {
    await File(abs('外部.md')).writeAsString('external body');
    await Directory(abs('资料')).create();
    await File(abs('资料/内部.md')).writeAsString('inner');

    final fresh = VaultNotesRepository.atRoot(tempDir.path);
    await fresh.init();
    addTearDown(fresh.close);

    final root = await fresh.childrenOf(null);
    expect(
      root.map((n) => n.title).toSet(),
      unorderedEquals({'外部', '资料'}),
    );

    final folder = root.firstWhere((n) => n.title == '资料');
    expect(folder.isFolder, isTrue);
    final inside = await fresh.childrenOf(folder.id);
    expect(inside.map((n) => n.title), contains('内部'));

    final external = root.firstWhere((n) => n.title == '外部');
    expect(external.content, 'external body');
    expect(await fresh.readBody(external.id), 'external body');
  });

  test('新建、预览、读写正文与改名保持 id 稳定', () async {
    final note = await repo.createNode(
      isFolder: false,
      title: 'Hello',
      content: 'first line\nsecond',
    );
    expect(note.title, 'Hello');
    expect(File(abs('Hello.md')).existsSync(), isTrue);

    final list = await repo.childrenOf(null);
    expect(list.single.title, 'Hello');
    expect(list.single.content, 'first line');
    expect(list.single.id, note.id);

    expect(await repo.readBody(note.id), 'first line\nsecond');
    await repo.writeBody(note.id, 'updated body');
    expect(await repo.readBody(note.id), 'updated body');

    await repo.rename(note.id, 'World');
    final after = await repo.nodeById(note.id);
    expect(after!.title, 'World');
    expect(await repo.readBody(note.id), 'updated body');
    expect(File(abs('Hello.md')).existsSync(), isFalse);
    expect(File(abs('World.md')).existsSync(), isTrue);

    expect(await repo.hasUserContent(), isTrue);

    // 正文指纹用于检测外部修改：文件丢失时返回 missing，正常时非空。
    expect(await repo.bodyFingerprint(note.id), isNot('missing'));
    File(abs('World.md')).deleteSync();
    expect(await repo.bodyFingerprint(note.id), 'missing');
  });

  test('同名与改名冲突自动加后缀', () async {
    final a = await repo.createNode(isFolder: false, title: 'A');
    final lower = await repo.createNode(isFolder: false, title: 'a');
    final b = await repo.createNode(isFolder: false, title: 'B');
    expect(a.title, 'A');
    // 大小写不敏感：a 与 A 被视为同名。
    expect(lower.title, 'a (2)');

    await repo.rename(b.id, 'A');
    expect((await repo.nodeById(b.id))!.title, 'A (3)');
  });

  test('改名文件夹同时迁移子树路径', () async {
    final folder = await repo.createNode(isFolder: true, title: 'F');
    final note = await repo.createNode(
      isFolder: false,
      title: 'A',
      parentId: folder.id,
      content: 'body',
    );
    await repo.rename(folder.id, 'G');

    expect((await repo.nodeById(folder.id))!.title, 'G');
    final inside = await repo.childrenOf(folder.id);
    expect(inside.single.title, 'A');
    expect(await repo.readBody(note.id), 'body');
    expect(Directory(abs('F')).existsSync(), isFalse);
    expect(Directory(abs('G')).existsSync(), isTrue);
  });

  test('移动与同层排序', () async {
    final folder = await repo.createNode(isFolder: true, title: 'F');
    final a = await repo.createNode(isFolder: false, title: 'A');
    final b = await repo.createNode(isFolder: false, title: 'B');

    await repo.move([a.id, b.id], folder.id);
    final inside = await repo.childrenOf(folder.id);
    expect(inside.map((n) => n.title).toList(), ['A', 'B']);
    expect(inside.every((n) => n.parentId == folder.id), isTrue);
    expect(
      (await repo.childrenOf(null)).map((n) => n.title).toList(),
      isNot(contains('A')),
    );

    await repo.reorder(folder.id, [b.id, a.id]);
    expect(
      (await repo.childrenOf(folder.id)).map((n) => n.title).toList(),
      ['B', 'A'],
    );
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

  test('移入回收站、恢复与永久删除', () async {
    final folder = await repo.createNode(isFolder: true, title: 'Docs');
    final child = await repo.createNode(
      isFolder: false,
      title: 'Readme',
      parentId: folder.id,
      content: 'body',
    );
    final temp = await repo.createNode(isFolder: false, title: 'Temp');

    // 同时选中祖先与子项时只产生一条回收站记录。
    await repo.moveToTrash([folder.id, child.id]);
    final trashed = await repo.listTrash();
    expect(trashed.length, 1);
    expect(trashed.single.entry.isFolder, isTrue);
    expect(trashed.single.toNode().title, 'Docs');
    expect(
      (await repo.childrenOf(null)).map((n) => n.title).toList(),
      isNot(contains('Docs')),
    );

    await repo.restore([folder.id]);
    final root = await repo.childrenOf(null);
    expect(root.map((n) => n.title), contains('Docs'));
    final restored = root.firstWhere((n) => n.title == 'Docs');
    expect(restored.id, folder.id);
    expect(
      (await repo.childrenOf(folder.id)).map((n) => n.title),
      contains('Readme'),
    );

    await repo.moveToTrash([temp.id]);
    expect((await repo.listTrash()).length, 1);
    await repo.purge([temp.id]);
    expect(await repo.listTrash(), isEmpty);
  });

  test('恢复遇到重名时加后缀', () async {
    final old = await repo.createNode(
      isFolder: false,
      title: 'N',
      content: 'old',
    );
    await repo.moveToTrash([old.id]);

    final fresh = await repo.createNode(
      isFolder: false,
      title: 'N',
      content: 'new',
    );
    expect(fresh.title, 'N');

    await repo.restore([old.id]);
    final titles = (await repo.childrenOf(null)).map((n) => n.title).toList();
    expect(titles.toSet(), unorderedEquals({'N', 'N (2)'}));
  });

  test('搜索、最近与统计', () async {
    final folder = await repo.createNode(isFolder: true, title: 'Work');
    await repo.createNode(
      isFolder: false,
      title: 'Plan',
      parentId: folder.id,
      content: 'alpha 项目',
    );
    await repo.createNode(
      isFolder: false,
      title: 'Ideas',
      content: 'beta',
    );

    final hits = await repo.search('alpha');
    expect(hits.map((n) => n.title).toList(), ['Plan']);
    expect(hits.single.content, 'alpha 项目');
    expect(
      (await repo.search('PLAN')).map((n) => n.title).toList(),
      ['Plan'],
    );
    expect(await repo.search(''), isEmpty);

    final recent = await repo.recent();
    expect(recent.length, 2);
    expect(recent.any((n) => n.isFolder), isFalse);
    expect(
      recent.map((n) => n.title).toSet(),
      unorderedEquals({'Plan', 'Ideas'}),
    );

    final stats = await repo.statistics();
    expect(stats.folders, 1);
    expect(stats.articles, 2);
    expect(stats.words, 4);
    expect(stats.recycled, 0);
    expect(stats.lastEditedAt, greaterThan(0));
  });

  test('replaceAll 全量导入并清理旧内容', () async {
    await repo.createNode(isFolder: false, title: 'Old', content: 'legacy');
    await repo.createNode(isFolder: true, title: 'Keep');

    await repo.replaceAll([
      _node(id: 'f-archive', isFolder: true, title: 'Archive'),
      _node(
        id: 'n-doc1',
        isFolder: false,
        title: 'Doc1',
        content: 'hello',
        parentId: 'f-archive',
      ),
      _node(
        id: 'n-doc2',
        isFolder: false,
        title: 'Doc2',
        content: 'root',
        sortOrder: 1,
        updatedAt: 3000,
      ),
    ]);

    expect(File(abs('Old.md')).existsSync(), isFalse);
    expect(Directory(abs('Keep')).existsSync(), isFalse);
    expect(Directory(abs('Archive')).existsSync(), isTrue);
    expect(File(abs('Archive/Doc1.md')).existsSync(), isTrue);
    expect(File(abs('Doc2.md')).existsSync(), isTrue);

    final root = await repo.childrenOf(null);
    expect(
      root.map((n) => n.title).toSet(),
      unorderedEquals({'Archive', 'Doc2'}),
    );
    expect(await repo.readBody('n-doc1'), 'hello');
    final docs = await repo.childrenOf('f-archive');
    expect(docs.single.title, 'Doc1');
    expect(docs.single.parentId, 'f-archive');
  });

  test('replaceAll 将回收站节点写入 trash 并保留子树内容', () async {
    await repo.replaceAll([
      _node(id: 'n-live', isFolder: false, title: 'Live', content: 'live'),
      _node(
        id: 'f-trash',
        isFolder: true,
        title: 'TrashFolder',
        isRecycled: true,
        deletedAt: 5000,
      ),
      _node(
        id: 'n-child',
        isFolder: false,
        title: 'Child',
        content: 'child body',
        parentId: 'f-trash',
        isRecycled: true,
        deletedAt: 5000,
      ),
    ]);

    final root = await repo.childrenOf(null);
    expect(root.map((n) => n.title).toList(), ['Live']);

    final trash = await repo.listTrash();
    expect(trash.length, 1);
    expect(trash.single.entry.isFolder, isTrue);
    expect(trash.single.entry.originalPath, 'TrashFolder');

    final all = await repo.allNodes();
    expect(
      all.where((n) => n.isRecycled).map((n) => n.title).toSet(),
      unorderedEquals({'TrashFolder', 'Child'}),
    );

    await repo.restore([trash.single.entry.id]);
    final restored = (await repo.childrenOf(null))
        .firstWhere((n) => n.title == 'TrashFolder');
    final children = await repo.childrenOf(restored.id);
    expect(children.map((n) => n.title).toList(), ['Child']);
    expect(await repo.readBody(children.single.id), 'child body');
  });
}
