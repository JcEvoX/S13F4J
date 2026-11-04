import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/plugins/builtin_plugins.dart';
import 'package:notepad/plugins/plugin_model.dart';

void main() {
  group('PluginManifest 命名空间与卸载语义', () {
    test('未声明 uninstallable 时：外部可卸载，内置不可卸载', () {
      const external = PluginManifest(
        id: 'ext.demo',
        name: 'demo',
        version: '1.0.0',
        description: '',
        capability: 'file.browser',
      );
      const builtin = PluginManifest(
        id: 'builtin.demo',
        name: 'demo',
        version: '1.0.0',
        description: '',
        capability: 'file.browser',
        builtin: true,
      );
      expect(external.canUninstall, isTrue);
      expect(builtin.canUninstall, isFalse);
    });

    test('内置笔记与文件阅读可卸载（= 停用并保留数据）', () {
      expect(builtinNotesPlugin().canUninstall, isTrue);
      expect(builtinFileBrowserPlugin().canUninstall, isTrue);
    });

    test('namespace / uninstallable / schema 经 JSON 往返保持不变', () {
      final restored = PluginManifest.fromJson(
        builtinNotesPlugin().toJson(),
      );
      expect(restored.namespace, 'notes');
      expect(restored.schema, 1);
      expect(restored.canUninstall, isTrue);
    });

    test('旧 manifest 缺字段时使用默认值', () {
      final manifest = PluginManifest.fromJson({
        'id': 'ext.legacy',
        'name': 'legacy',
        'capability': 'file.browser',
      });
      expect(manifest.namespace, isNull);
      expect(manifest.schema, 1);
      expect(manifest.canUninstall, isTrue);
    });

    test('ownsNamespace 匹配同名与点分前缀，不误伤相似前缀', () {
      final files = builtinFileBrowserPlugin();
      expect(files.ownsNamespace('files'), isTrue);
      expect(files.ownsNamespace('files.p-01'), isTrue);
      expect(files.ownsNamespace('filesystem'), isFalse);
      expect(files.ownsNamespace('notes'), isFalse);

      final notes = builtinNotesPlugin();
      expect(notes.ownsNamespace('notes'), isTrue);
    });
  });
}
