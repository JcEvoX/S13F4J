import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/core/storage/storage_capability.dart';
import 'package:notepad/data/notes_repository.dart';
import 'package:notepad/data/vault/vault_store.dart';
import 'package:notepad/services/namespace_registry.dart';
import 'package:path/path.dart' as p;

NamespaceDescriptor _notes() => const NamespaceDescriptor(
      id: 'notes',
      pluginId: 'builtin.notes',
      displayName: '笔记',
      createdAt: 1,
    );

NamespaceDescriptor _project(String id, String root) => NamespaceDescriptor(
      id: 'files.$id',
      pluginId: 'builtin.files',
      root: root,
      displayName: id,
      trashDriver: false,
      createdAt: 2,
    );

void main() {
  late Directory tempDir;
  late VaultStore store;
  late NamespaceRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notepad_registry_');
    store = VaultStore(tempDir.path);
    registry = NamespaceRegistry(store: store);
    await registry.load();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> writeTrash(String root, List<String> ids) async {
    for (final id in ids) {
      await Directory(p.join(root, '.notepad/trash/items', id))
          .create(recursive: true);
    }
    await File(p.join(root, '.notepad/trash/manifest.json')).writeAsString(
      jsonEncode({
        'schema': 1,
        'entries': [
          for (final id in ids)
            {
              'id': id,
              'kind': 'note',
              'originalPath': '$id.md',
              'trashPath': 'items/$id/$id.md',
              'deletedAt': 1,
            },
        ],
      }),
    );
  }

  test('ensureNotes 幂等并写入注册表文件', () async {
    await registry.ensureNotes();
    await registry.ensureNotes();

    final all = await registry.all();
    expect(all.map((n) => n.id), ['notes']);
    expect(
        File(p.join(tempDir.path, NamespaceRegistry.registryPath)).existsSync(),
        isTrue);

    final reloaded = NamespaceRegistry(store: store);
    await reloaded.load();
    expect((await reloaded.resolve('notes'))?.state, 'active');
  });

  test('停用只改 state，驱动声明与数据保持不变', () async {
    await registry.register(_notes());
    await registry.register(_project('p-01', '/abs/p-01'));

    await registry.deactivate('builtin.notes');

    final notes = (await registry.resolve('notes'))!;
    expect(notes.state, 'disabled');
    expect(notes.backupDriver, isTrue);
    expect(notes.trashDriver, isTrue);
    expect((await registry.resolve('files.p-01'))!.state, 'active');
  });

  test('重新启用恢复 active，文件项目不会被改成提供回收站', () async {
    await registry.register(_notes());
    await registry.register(_project('p-01', '/abs/p-01'));

    await registry.deactivate('builtin.files');
    await registry.activate('builtin.files');

    final project = (await registry.resolve('files.p-01'))!;
    expect(project.state, 'active');
    expect(project.backupDriver, isTrue);
    expect(project.trashDriver, isFalse);
  });

  test('兼容旧注册表：停用时驱动被置 false，启用后按能力默认值恢复', () async {
    await registry.register(
      _notes().copyWith(
        state: 'disabled',
        backupDriver: false,
        trashDriver: false,
      ),
    );

    await registry.activate('builtin.notes');

    final notes = (await registry.resolve('notes'))!;
    expect(notes.state, 'active');
    expect(notes.backupDriver, isTrue);
    expect(notes.trashDriver, isTrue);
  });

  test('syncPluginStates 只修正与期望不一致的记录', () async {
    await registry.register(_notes());
    await registry.register(_project('p-01', '/abs/p-01'));
    await registry.deactivate('builtin.files');

    await registry.syncPluginStates({
      'builtin.notes': false,
      'builtin.files': true,
    });

    expect((await registry.resolve('notes'))!.state, 'disabled');
    expect((await registry.resolve('files.p-01'))!.state, 'active');

    final reloaded = NamespaceRegistry(store: store);
    await reloaded.load();
    expect((await reloaded.resolve('notes'))!.state, 'disabled');
  });

  test('forget：回收站为空时移除记录', () async {
    await registry.register(_notes());
    await registry.forget('notes');
    expect(await registry.resolve('notes'), isNull);
  });

  test('forget：vault 内命名空间回收站非空时拒绝并保留记录', () async {
    await registry.register(_notes());
    await writeTrash(tempDir.path, ['n1', 'n2']);

    expect(await registry.trashEntryCount('notes'), 2);
    await expectLater(
      registry.forget('notes'),
      throwsA(
        isA<NotesException>().having((e) => e.code, 'code', 'E-CONFLICT'),
      ),
    );
    expect(await registry.resolve('notes'), isNotNull);
  });

  test('forget：外部根命名空间同样检查回收站', () async {
    final external = await Directory.systemTemp.createTemp('notepad_ext_');
    addTearDown(() async {
      if (external.existsSync()) await external.delete(recursive: true);
    });
    await registry.register(_project('p-02', external.path));
    await writeTrash(external.path, ['x']);

    await expectLater(
      registry.forget('files.p-02'),
      throwsA(isA<NotesException>()),
    );

    await File(p.join(external.path, '.notepad/trash/manifest.json'))
        .writeAsString(jsonEncode({'schema': 1, 'entries': []}));
    await Directory(p.join(external.path, '.notepad/trash/items/x'))
        .delete(recursive: true);
    await registry.forget('files.p-02');
    expect(await registry.resolve('files.p-02'), isNull);
  });

  test('forget：manifest 损坏时以 items 目录兜底计数', () async {
    await registry.register(_notes());
    await Directory(p.join(tempDir.path, '.notepad/trash/items/orphan'))
        .create(recursive: true);
    await File(p.join(tempDir.path, '.notepad/trash/manifest.json'))
        .writeAsString('{broken');

    expect(await registry.trashEntryCount('notes'), 1);
    await expectLater(
      registry.forget('notes'),
      throwsA(isA<NotesException>()),
    );
  });
}
