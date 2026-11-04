import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/workbench/base/context_keys.dart';
import 'package:notepad/workbench/base/disposable.dart';
import 'package:notepad/workbench/base/fuzzy.dart';
import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/base/when_clause.dart';

void main() {
  group('ResourceUri', () {
    test('解析与规范化', () {
      final uri = ResourceUri.parse('notes:/工作//周报.md');
      expect(uri.scheme, 'notes');
      expect(uri.path, '/工作/周报.md');
      expect(uri.basename, '周报.md');
      expect(uri.extname, '.md');
      expect(uri.toString(), 'notes:/工作/周报.md');
      expect(ResourceUri.parse('notes:').isRoot, isTrue);
      expect(ResourceUri('files.p-01').toString(), 'files.p-01:/');
    });

    test('namespace id 中的点与横线可作为 scheme', () {
      final uri = ResourceUri.parse('files.p-01:/lib/main.dart');
      expect(uri.scheme, 'files.p-01');
      expect(uri.segments, ['lib', 'main.dart']);
    });

    test('拒绝 .. 与缺失 scheme', () {
      expect(() => ResourceUri.parse('notes:/a/../b'), throwsFormatException);
      expect(() => ResourceUri.parse('/no-scheme'), throwsFormatException);
      expect(() => ResourceUri('a/b'), throwsFormatException);
      expect(ResourceUri.tryParse('::'), isNull);
    });

    test('parent / join / contains', () {
      final file = ResourceUri.parse('notes:/a/b/c.md');
      expect(file.parent.toString(), 'notes:/a/b');
      expect(file.parent.parent.parent.isRoot, isTrue);
      expect(file.parent.join('d.md').toString(), 'notes:/a/b/d.md');
      expect(ResourceUri('notes').parent.isRoot, isTrue);
      expect(ResourceUri.parse('notes:/a').contains(file), isTrue);
      expect(
          ResourceUri.parse('notes:/a')
              .contains(ResourceUri.parse('notes:/ab')),
          isFalse);
      expect(ResourceUri('notes').contains(file), isTrue);
      expect(ResourceUri('files.p').contains(file), isFalse);
    });

    test('扩展名：点文件与多点文件名', () {
      expect(ResourceUri.parse('x:/.gitignore').extname, '');
      expect(ResourceUri.parse('x:/a.tar.GZ').extname, '.gz');
      expect(ResourceUri.parse('x:/Makefile').extname, '');
    });

    test('值语义：相等与哈希', () {
      expect(ResourceUri.parse('a:/x'), ResourceUri.parse('a:/x/'));
      expect({ResourceUri.parse('a:/x')}.contains(ResourceUri.parse('a:/x')),
          isTrue);
    });
  });

  group('WhenClause', () {
    bool eval(String when, Map<String, Object?> ctx) =>
        WhenClause.parse(when).evaluate(ctx);

    test('空子句恒为真，裸 key 看真值', () {
      expect(eval('', {}), isTrue);
      expect(eval('a', {'a': true}), isTrue);
      expect(eval('a', {'a': false}), isFalse);
      expect(eval('a', {}), isFalse);
      expect(eval('a', {'a': ''}), isFalse);
      expect(eval('a', {'a': 0}), isFalse);
      expect(eval('a', {'a': 'x'}), isTrue);
    });

    test('逻辑运算与括号，&& 优先于 ||', () {
      expect(eval('a && b', {'a': true, 'b': true}), isTrue);
      expect(eval('a && b', {'a': true}), isFalse);
      expect(eval('a || b', {'b': true}), isTrue);
      expect(eval('!a', {}), isTrue);
      expect(eval('a || b && c', {'a': true}), isTrue);
      expect(eval('(a || b) && c', {'a': true}), isFalse);
      expect(eval('!(a && b)', {'a': true}), isTrue);
    });

    test('相等 / 不等 / 数值比较', () {
      expect(eval("scheme == notes", {'scheme': 'notes'}), isTrue);
      expect(eval("scheme == 'notes'", {'scheme': 'notes'}), isTrue);
      expect(eval("scheme != notes", {'scheme': 'files'}), isTrue);
      expect(eval('n > 0', {'n': 2}), isTrue);
      expect(eval('n >= 2', {'n': 2}), isTrue);
      expect(eval('n < 2', {'n': 2}), isFalse);
      expect(eval('n <= 2', {'n': 2}), isTrue);
      expect(eval('flag == true', {'flag': true}), isTrue);
      expect(eval('flag == false', {}), isTrue);
      expect(eval('missing == notes', {}), isFalse);
      expect(eval('n > 0', {}), isFalse);
    });

    test('收集引用的 key', () {
      expect(
        WhenClause.parse("a && (b == 1 || !c)").keys,
        {'a', 'b', 'c'},
      );
    });

    test('语法错误抛 FormatException；tryParse 退化为恒假', () {
      for (final bad in ['a &&', '(a', 'a ==', '== a', "a == 'x", 'a b']) {
        expect(() => WhenClause.parse(bad), throwsFormatException, reason: bad);
      }
      expect(WhenClause.tryParse('a &&').evaluate({'a': true}), isFalse);
    });
  });

  group('ContextKeyService', () {
    test('值不变不通知，变化才通知', () {
      final keys = ContextKeyService();
      var notified = 0;
      keys.addListener(() => notified++);
      keys.set('a', 1);
      keys.set('a', 1);
      keys.set('b', null);
      keys.setAll({'a': 1});
      expect(notified, 1);
      keys.set('a', 2);
      expect(notified, 2);
      keys.remove('missing');
      expect(notified, 2);
      keys.remove('a');
      expect(notified, 3);
    });

    test('evaluate 支持覆盖值且不污染状态', () {
      final keys = ContextKeyService()..set('a', true);
      expect(keys.evaluate('a && b'), isFalse);
      expect(keys.evaluate('a && b', overrides: {'b': true}), isTrue);
      expect(keys.evaluate('a && b'), isFalse);
      expect(keys.evaluate(null), isTrue);
      expect(keys.evaluate('  '), isTrue);
    });
  });

  group('Disposable', () {
    test('toDisposable 幂等', () {
      var count = 0;
      final d = toDisposable(() => count++);
      d.dispose();
      d.dispose();
      expect(count, 1);
    });

    test('DisposableStore 逆序释放；释放后加入的立即释放；单项异常不影响其余', () {
      final order = <int>[];
      final store = DisposableStore()
        ..add(toDisposable(() => order.add(1)))
        ..add(toDisposable(() => throw StateError('boom')))
        ..add(toDisposable(() => order.add(3)));
      store.dispose();
      expect(order, [3, 1]);
      expect(store.isDisposed, isTrue);

      var late = false;
      store.add(toDisposable(() => late = true));
      expect(late, isTrue);
    });

    test('clear 后可继续使用', () {
      final store = DisposableStore();
      var count = 0;
      store.add(toDisposable(() => count++));
      store.clear();
      expect(count, 1);
      store.add(toDisposable(() => count++));
      store.dispose();
      expect(count, 2);
    });
  });

  group('fuzzyScore', () {
    test('子序列匹配，不匹配为 null', () {
      expect(fuzzyScore('abc', 'a_b_c'), isNotNull);
      expect(fuzzyScore('abc', 'acb'), isNull);
      expect(fuzzyScore('', 'anything'), 0);
      expect(fuzzyScore('ABC', 'abc'), isNotNull);
    });

    test('连续与词首命中得分更高', () {
      final contiguous = fuzzyScore('note', 'notes.md')!;
      final scattered = fuzzyScore('note', 'n_o_t_e')!;
      expect(contiguous, greaterThan(scattered));
      expect(fuzzyScore('md', 'a/readme.md')!,
          greaterThan(fuzzyScore('md', 'amdz')!));
    });
  });
}
