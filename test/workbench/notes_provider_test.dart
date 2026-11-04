import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/notes_repository.dart';
import 'package:notepad/data/vault/vault_notes_repository.dart';
import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/extensions/notes_extension.dart';
import 'package:notepad/workbench/services/file_system.dart';

void main() {
  late Directory tempDir;
  late NotesRepository repo;
  late NotesFileSystemProvider fs;

  ResourceUri notes(String path) => ResourceUri('notes', path);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notepad_wb_notes_');
    repo = VaultNotesRepository.atRoot(tempDir.path);
    await repo.init();
    fs = NotesFileSystemProvider(repo);
  });

  tearDown(() async {
    fs.dispose();
    await repo.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<List<String>> names(String path) async =>
      [for (final e in await fs.readDirectory(notes(path))) e.name];

  test('笔记 = 标题.md，文件夹 = 标题；顺序沿用仓库排序', () async {
    final folder = await repo.createNode(isFolder: true, title: '工作');
    await repo.createNode(isFolder: false, title: '周报', parentId: folder.id, content: '本周');
    await repo.createNode(isFolder: false, title: '随笔', content: 'x');

    expect(await names('/'), ['工作', '随笔.md']);
    expect(await names('/工作'), ['周报.md']);
    final entries = await fs.readDirectory(notes('/'));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.last.type, ResourceType.file);
  });

  test('stat / readText / writeText 经由仓库往返', () async {
    await repo.createNode(isFolder: false, title: 'a', content: 'hello');
    expect((await fs.stat(notes('/'))).isDirectory, isTrue);
    expect((await fs.stat(notes('/a.md'))).type, ResourceType.file);
    expect(await fs.readText(notes('/a.md')), 'hello');

    await fs.writeText(notes('/a.md'), 'changed');
    expect(await fs.readText(notes('/a.md')), 'changed');
    final id = await fs.nodeIdOf(notes('/a.md'));
    expect(await repo.readBody(id!), 'changed');
  });

  test('不存在 / 类型不符给出明确错误码', () async {
    await repo.createNode(isFolder: true, title: 'dir');
    await repo.createNode(isFolder: false, title: 'a');
    Matcher code(String c) =>
        throwsA(isA<FileSystemError>().having((e) => e.code, 'code', c));
    await expectLater(fs.stat(notes('/nope.md')), code('E-NOT-FOUND'));
    await expectLater(fs.readText(notes('/dir')), code('E-UNSUPPORTED'));
    await expectLater(fs.readDirectory(notes('/a.md')), code('E-UNSUPPORTED'));
    expect(await fs.nodeIdOf(notes('/nope.md')), isNull);
  });

  test('createFile 自动补 .md、冲突时由仓库改名，并广播变更', () async {
    final events = <ResourceUri>[];
    final sub = fs.onDidChange.listen(events.add);

    final first = await fs.createFile(notes('/'), '想法');
    final second = await fs.createFile(notes('/'), '想法.md');
    expect(first.path, '/想法.md');
    expect(second.path, isNot(first.path));
    expect(await names('/'), containsAll([first.basename, second.basename]));

    final folder = await fs.createDirectory(notes('/'), '项目');
    expect(folder.path, '/项目');
    final nested = await fs.createFile(folder, 'x.md', content: 'body');
    expect(await fs.readText(nested), 'body');

    await Future<void>.delayed(Duration.zero);
    expect(events.length, 4);
    await sub.cancel();
  });

  test('在笔记里创建文件需要父级是文件夹；空名称被拒绝', () async {
    await repo.createNode(isFolder: false, title: 'a');
    await expectLater(
      fs.createFile(notes('/a.md'), 'b'),
      throwsA(isA<FileSystemError>()),
    );
    await expectLater(
      fs.createFile(notes('/'), '  '),
      throwsA(isA<FileSystemError>()),
    );
    await expectLater(
      fs.createFile(notes('/'), '.md'),
      throwsA(isA<FileSystemError>()),
    );
  });

  test('rename 返回新资源；根不能重命名 / 删除', () async {
    await repo.createNode(isFolder: false, title: 'old', content: 'c');
    final renamed = await fs.rename(notes('/old.md'), 'new');
    expect(renamed.path, '/new.md');
    expect(await fs.readText(renamed), 'c');
    await expectLater(fs.stat(notes('/old.md')), throwsA(isA<FileSystemError>()));

    await expectLater(fs.rename(notes('/'), 'x'), throwsA(isA<FileSystemError>()));
    await expectLater(fs.delete(notes('/')), throwsA(isA<FileSystemError>()));
  });

  test('delete 进入回收站（可恢复），不再出现在目录里', () async {
    final node = await repo.createNode(isFolder: false, title: 'gone', content: 'c');
    expect(fs.deleteGoesToTrash, isTrue);
    await fs.delete(notes('/gone.md'));
    expect(await names('/'), isEmpty);
    final trashed = await repo.listTrash();
    expect(trashed.map((e) => e.toNode().id), contains(node.id));
  });

  test('displayName：笔记去掉 .md，其余保持', () {
    expect(fs.displayName(notes('/工作/周报.md')), '周报');
    expect(fs.displayName(notes('/工作')), '工作');
    expect(fs.displayName(notes('/')), '笔记');
  });

  test('标题在同级内唯一：文件夹与笔记同名时仓库给笔记加后缀，路径仍可解析', () async {
    await repo.createNode(isFolder: true, title: 'x');
    await repo.createNode(isFolder: false, title: 'x');
    expect(await names('/'), unorderedEquals(['x', 'x (2).md']));
    expect((await fs.stat(notes('/x'))).isDirectory, isTrue);
    expect((await fs.stat(notes('/x (2).md'))).isDirectory, isFalse);
  });
}
