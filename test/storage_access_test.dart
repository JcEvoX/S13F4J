import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/services/storage_access.dart';

class _FakeAccess implements StorageAccess {
  _FakeAccess({this.granted = false, this.grantOnRequest = false});

  bool granted;
  final bool grantOnRequest;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<void> openSystemSettings() async => settingsOpened++;
}

void main() {
  late StorageAccess original;
  setUp(() => original = StorageAccess.instance);
  tearDown(() => StorageAccess.instance = original);

  test('已授权：不弹窗、不申请', () async {
    final fake = _FakeAccess(granted: true);
    StorageAccess.instance = fake;
    var asked = false;
    final ok = await ensureStorageAccess(
      confirm: (_, __) async {
        asked = true;
        return true;
      },
      notify: (_) {},
    );
    expect(ok, isTrue);
    expect(asked, isFalse);
    expect(fake.requests, 0);
  });

  test('未授权：先说明用途，同意后向系统申请', () async {
    final fake = _FakeAccess(grantOnRequest: true);
    StorageAccess.instance = fake;
    String? shown;
    final ok = await ensureStorageAccess(
      purpose: '导入文件夹',
      confirm: (title, message) async {
        shown = message;
        return true;
      },
      notify: (_) {},
    );
    expect(ok, isTrue);
    expect(shown, contains('导入文件夹'));
    expect(fake.requests, 1);
  });

  test('用户在说明里取消：不向系统申请', () async {
    final fake = _FakeAccess();
    StorageAccess.instance = fake;
    final ok = await ensureStorageAccess(
      confirm: (_, __) async => false,
      notify: (_) {},
    );
    expect(ok, isFalse);
    expect(fake.requests, 0);
  });

  test('系统拒绝：提示并引导到系统设置', () async {
    final fake = _FakeAccess();
    StorageAccess.instance = fake;
    final messages = <String>[];
    final ok = await ensureStorageAccess(
      purpose: '写入备份文件夹',
      confirm: (_, __) async => true,
      notify: messages.add,
    );
    expect(ok, isFalse);
    expect(messages.single, contains('写入备份文件夹'));
    expect(fake.settingsOpened, 1);
  });
}
