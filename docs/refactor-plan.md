# NotePad 文件化改造方案（v2）

> 基于《架构设计方案（地基版）》评审结论修订
> 日期：2026-10-31
> 适用对象：当前 Flutter 工程（lib/ 下 sqflite 权威实现）

## 0. 一句话结论

在现有工程上先加一层 `NotesRepository` 接缝，把 UI 与 SQLite 解耦；再实现文件存储内核；最后用一次性迁移器把旧库转成 vault。不做真·跨设备同步，插件保持声明式能力包。

## 1. 已锁定的决策

| # | 决策点 | 结论 | 理由 |
|---|---|---|---|
| D1 | 同步范围 | v2 只做单机 + 系统备份 + 手动/WebDAV zip；iCloud Drive 实时同步不在本期 | 原方案把「设备备份」误当「同步」；真同步要 ubiquity container，冲突处理成本完全不同 |
| D2 | 元数据权威 | 正文 md 保持纯净；`tree.json` 承载 id / 顺序 / 创建时间 / 标签 / 收藏 | iCloud 按文件同步，front matter 会污染正文；单一 sidecar 便于重建与迁移 |
| D3 | 标题来源 | 标题 = 文件名（去扩展名），文件夹名 = 目录名 | 避免 title 与 path 双份漂移，外部改名自动生效 |
| D4 | 附件 | `<vault>/assets/<noteId>/`，正文用相对路径引用 | 不随文档改名失效；避免 dot 目录在 Files/SAF 中不可见 |
| D5 | 回收站 | 内容 + manifest 都在 `<vault>/.notepad/trash/` | appDataRoot 会随卸载清空，放那里等于删了没救 |
| D6 | 注册表 | 权威在 `<vault>/.notepad/registry.json`，appDataRoot 仅做启动缓存 | 换机 / 恢复后仍能发现命名空间 |
| D7 | 索引 | `<appDataRoot>/index/`，可随时删除重建，绝不存用户意图 | 索引是派生数据 |
| D8 | 插件 | 声明式能力包 + 资源包，无第三方动态代码 | Flutter / iOS 无法安全动态加载；现有 `PluginManifest` 已是声明式 |
| D9 | 笔记插件 | 内置但可「卸载」（= 停用能力），数据、registry、trash 保留 | 满足原方案「可装可卸」 |
| D10 | 改造方式 | Repository 接缝 + 双实现灰度，不做大爆炸重写 | 现有 UI 与 DB 强耦合，直接替换风险高 |

> 若 D1 改为「要做真同步」，本方案第 2、3、4 节都要重做路径与冲突模型，建议单独出方案。

## 2. 目标结构

### 2.1 分层

```
UI (现有 pages)
   ↓ 只依赖
NotesRepository (接口)
   ↓
VaultNotesRepository（文件实现）        SqliteNotesRepository（过渡期保留）
   ↓
VaultStore / TreeStore / FilenamePolicy / TrashService / VaultIndex / NamespaceRegistry
   ↓
StorageRoot (SandboxRoot；未来 SafRoot)
```

### 2.2 磁盘布局

```
<vaultRoot>/                      # iOS: Documents/Notepad ; Android: files/Notepad
├─ 工作/
│  └─ 周报.md
├─ 日记.md
├─ assets/
│  └─ <noteId>/xxx.png
└─ .notepad/
   ├─ registry.json               # 命名空间注册（权威）
   ├─ tree.json                   # id / 顺序 / 时间 / 标签 / 收藏（权威用户意图）
   ├─ trash/
   │  ├─ manifest.json
   │  └─ items/<id>/...           # 保留原相对结构
   └─ migration.json              # 迁移记录（来源 hash / 时间 / 结果）

<appDataRoot>/                    # iOS: Library/Application Support/Notepad ; Android 内部 files
├─ index/notes_index.json         # 派生：path / title / mtime / size
├─ backups/notes/<ts>.zip         # 自动快照
└─ logs/
```

`Caches` 只放渲染 / 图片缓存，不放备份与索引。

### 2.3 平台注意事项（不落地的话「备份语义」是错的）

- iOS：`appDataRoot` 默认**会**进 iCloud 设备备份，需对 `index/`、`backups/`、`logs/` 设置 `NSURLIsExcludedFromBackupKey`（平台通道或现成插件实现）。`Documents` 只是设备备份范围，不是 iCloud Drive。
- Android：`allowBackup` 默认开，需用 `fullBackupContent` / `dataExtractionRules` 排除 `index/`、`backups/`。
- iOS 不要依赖 `FileSystemEntity.watch`；用「前台恢复 + 手动刷新」做对账。Android / 桌面可用 watch 做实时刷新。

## 3. 核心契约

### 3.1 tree.json

```json
{
  "schema": 1,
  "updatedAt": 1761800000000,
  "nodes": [
    {"id":"note-01","kind":"note","path":"工作/周报.md","order":0,"createdAt":1710000000000,"updatedAt":1761800000000,"tags":[],"favorite":false},
    {"id":"folder-01","kind":"folder","path":"工作","order":1,"createdAt":1710000000000}
  ]
}
```

规则：

- `path` 相对 vaultRoot；`order` 只在**同一父目录**内比较。
- 列目录只需 `list(目录)` + tree 顺序，不做全库扫描。
- 对账：磁盘新增 → 生成 id 入 tree；tree 有而磁盘无 → 标记 `missing`（UI 灰态，可丢弃）；外部改名视为删 + 增（v2 不做内容指纹追踪）。
- tree.json 丢失 / 损坏 → 全盘扫描重建，顺序按文件名自然排序，并写 `migration.json` 的 `rebuilt: true`；用户顺序丢失是已知代价。

### 3.2 文件名规则（`FilenamePolicy`）

- 非法字符 `\ / : * ? " < > |` 与换行 → `_`；首尾控制字符去掉。
- 统一 NFC；空标题 → `未命名`；长度按 UTF-8 255 字节截断（留后缀余量）。
- 同目录重名（大小写不敏感比较，兼容 APFS）自动加 ` (2)`。
- `.notepad`、`assets`、以 `.` 开头 保留为系统命名，用户不可用。

### 3.3 StorageRoot 接口

```dart
abstract class StorageRoot {
  Future<bool> exists(String rel);
  Future<List<StorageEntry>> list(String relDir);
  Future<String> readText(String rel);
  Future<void> writeTextAtomic(String rel, String text);
  Future<void> writeBytesAtomic(String rel, List<int> bytes);
  Future<void> rename(String fromRel, String toRel);
  Future<void> delete(String rel);
  Future<DateTime> modifiedAt(String rel);
  bool get supportsWatch;
}
```

- v2 只实现 `SandboxRoot`（dart:io，tmp + rename 同目录）。
- 预留 `SafRoot`（Android 外部树）与外部 vault，供 git / 文件阅读插件使用，不在本期。

### 3.4 NamespaceRegistry

命名空间自描述（避免与现有 `CapabilityRegistry` 混淆，新名字用 `NamespaceRegistry`）：

```json
{"schema":1,"namespaces":[
  {"id":"notes","pluginId":"builtin.notes","root":"Notepad","displayName":"笔记","createdAt":1761800000000,"schema":1}
]}
```

生命周期：

- `register` / `resolve` / `deactivate(pluginId)` / `activate(pluginId)` / `forget(namespaceId)`。
- 卸载插件 = `deactivate`，**不** `forget`；备份与回收站仍可 `resolve` 到已停用命名空间。
- `forget` 只给「彻底删除数据」的显式入口，UI 二次确认。

### 3.5 Trash

```json
// .notepad/trash/manifest.json
{"schema":1,"entries":[
  {"id":"note-01","kind":"note","origin":"notes","originalPath":"工作/周报.md","trashPath":"items/note-01/周报.md","deletedAt":1761800000000}
]}
```

- 删除 = 整棵子树移入 `items/<id>/`，manifest 记录原路径。
- 恢复 = `registry.resolve(origin)` → 原目录不存在则重建 → 同名加后缀。
- 「清空」才真正删；保留期策略放 M4，默认不自动清。

### 3.6 备份

- `createSnapshot(namespaceId)`：vault → 临时 zip（含 `.notepad`，排除 index），zip 内 `manifest.json`（schema、导出时间、文件清单 + sha256、app 版本），原子 rename 到 `backups/<ns>/<ts>.zip`。
- `restore(snapshot)`：解压到 `staging/` → 校验 manifest / hash → 加应用级写锁（禁编辑）→ 当前 vault 移到 `staging/old-<ts>/` → 替换 → 成功后清理；失败回滚。
- WebDAV 改为上传 zip 字节（`WebDavService` 需补 `uploadBytes`），目录 `/NotePadBackup` 保留；旧 JSON 只作为**导入**格式。

### 3.7 NotesRepository 接口

```dart
abstract class NotesRepository {
  Future<void> init();
  Future<List<NotePadNode>> childrenOf(String? folderId);
  Future<NotePadNode?> nodeById(String id);
  Future<String> readBody(String id);
  Future<void> writeBody(String id, String body);
  Future<NotePadNode> createNode({required bool isFolder, required String title});
  Future<void> rename(String id, String newTitle);
  Future<void> move(List<String> ids, String? targetFolderId);
  Future<void> reorder(String? folderId, List<String> orderedIds);
  Future<void> moveToTrash(List<String> ids);
  Future<List<TrashEntry>> listTrash();
  Future<void> restore(List<String> ids);
  Future<void> purge(List<String> ids);
  Future<List<NotePadNode>> search(String keyword);
  Future<List<NotePadNode>> recent({int limit});
  Future<NoteStatistics> statistics();
  Future<void> replaceAll(List<NotePadNode> nodes, {String? stagingDir});
}
```

- 列表接口返回的节点**不带 body**；编辑器调用 `readBody` 再取。`NotePadNode.content` 字段过渡期保留但默认空，避免一次性改全部 widget。
- 所有写操作走 `VaultStore` 内部串行队列，避免并发写 tree.json。

## 4. 旧数据迁移

### 4.1 触发

启动检测 `Documents/app_database.db` 存在，且 `.notepad/migration.json` 无成功记录 → 进入迁移页。

### 4.2 步骤（幂等、可重入）

1. 只读 DB 生成迁移计划：整表按 `parent_id` / `sort_order` 还原树，回收站节点单独归类。
2. 预检：标题清洗、重名、超长、emoji、NFC 冲突 → 生成冲突报告。
3. 建 vault；若已有 vault，则本次迁移落到 `<vault>/.notepad/migration/<ts>/` 后合并。
4. 逐节点写：文件夹 mkdir；文章原子写 md；`sort_order` → tree `order`；保留原 id、created / updated。
5. 回收站节点写入 `.notepad/trash/` + manifest。
6. 写 `tree.json` + `migration.json`（来源 hash、节点数、耗时）。
7. DB 改名 `app_database.db.migrated-<ts>`，**不删除**。
8. 抽样校验（节点数、body 长度、层级 depth）；不一致则整体失败，保留 DB 并回滚 vault。

### 4.3 旧 JSON 备份导入

复用 `BackupService.decodeBackup` 的节点数组 → 走 4.2 的 staging 写入器 → 预览后替换。保留 `format: 1` 兼容。

### 4.4 回滚

- 设置项 `storage.backend`（`sqlite` / `files`）+ `migration.ts`。
- 迁移失败或用户回退 → 删除 `migration.json`、把 `.migrated-*` 改回 `.db`，UI 回到旧实现；`SqliteNotesRepository` 保留到下一个大版本再删。

## 5. 里程碑（按依赖顺序）

### M0 · 接缝与安全网（不改用户可见行为）

- 新增 `lib/data/notes_repository.dart`、`lib/data/sqlite_notes_repository.dart`；`NoteProvider` 构造函数注入；`statistics_page`、`recent_page`、`backup_restore_page` 去掉直接 `NoteDao()`。
- 接口契约测试：以现有 NoteDao 行为为基线。
- 验收：功能零变化；`flutter analyze` 无新增告警；契约测试全绿。

### M1 · 文件内核（不接 UI）

- `lib/core/storage/storage_root.dart`、`storage_paths.dart`。
- `lib/data/vault/{vault_store, folder_fs, filename_policy, tree_store}.dart`。
- `lib/services/{namespace_registry, trash_service, vault_index}.dart`。
- `VaultNotesRepository` 实现同一接口；契约测试双跑（临时目录 fixture）。
- 用例：重名、emoji、超长名、大小写冲突、崩溃遗留 tmp、tree 损坏重建、外部新增 / 删除 / 改名对账。
- 验收：同一套契约测试全绿；基准脚本下 10k 文件单层目录列表 < 200ms。

### M2 · 迁移与切换

- `lib/data/migration/legacy_sqlite_migrator.dart`、`legacy_json_importer.dart`；`lib/ui/migration/`。
- 设置开关与失败回滚；`main.dart` 按 backend 决定初始化路径。
- 验收：真实结构 fixture（嵌套 / 回收站 / 重名 / 空标题 / emoji）迁移后文件树与 tree.json 完全对应；重复执行幂等；注入磁盘满 / 权限失败可回滚。

### M3 · UI 对接

- `home_page`：列表 / 拖拽排序 / 重命名 / 移动。
- `editor_page`：懒加载正文 + 防抖自动保存 + 写失败提示。
- `search_page`：索引标题 + 按需读正文。`recent_page` / `statistics_page` 走 repository；`recyclebin_page` 换 `TrashEntry`。
- 外部变更：前台恢复触发 `reconcile` + 刷新；编辑中的文件被外部改动 → 提示重载，不静默覆盖。
- 验收：手工矩阵（新建 / 改名 / 移动 / 拖拽 / 搜索 / 回收站 / 杀进程重开）+ 现有 widget 测试通过。

### M4 · 备份、trash 策略、平台排除项

- zip 快照 / 恢复（含 staging 与写锁）、WebDAV `uploadBytes`、自动备份改造、旧 JSON 导入入口。
- iOS / Android 备份排除配置（平台通道 + manifest 规则）。
- 验收：快照 → 改数据 → 恢复；恢复中途被杀可恢复；hash 校验失败可拒绝。

### M5 · 能力 / 插件语义

- `PluginManifest` 增 `namespace`、`uninstallable`、`schema`；`PluginManager.uninstall` 改为「停用 + 保留记录」；内置笔记允许卸载。
- 笔记停用后首页不显示入口，但备份 / 回收站仍可操作。
- `Capability` 增 `namespaceId` 与 `requiredPermissions`，`launch` 保留。
- 验收：卸载笔记 → 数据零变化 → 备份 / trash 可用 → 重装恢复入口。

### M6 · 明确不在本期

真 iCloud Drive 同步、git 插件、FTS 全文索引、附件插入 UI、加密、协作、桌面端正式支持。

## 6. 受影响文件清单

| 文件 | 处理 |
|---|---|
| `lib/data/app_database.dart` | M2 后冻结，M5 后删除 |
| `lib/data/note_dao.dart` | M0 包进 SqliteRepository，M5 删除 |
| `lib/models/note.dart` | M1 增 `path` / `bodyLoaded`；`isRecycled` 迁到 `TrashEntry` |
| `lib/state/note_provider.dart` | M0 注入 repository；M3 支持对账刷新 |
| `lib/ui/home/home_page.dart` | M3 重命名 / 移动 / 拖拽改写 |
| `lib/ui/editor/editor_page.dart` | M3 懒加载 + 原子写 + 失败提示 |
| `lib/ui/recyclebin/recyclebin_page.dart` | M3 换 TrashService |
| `lib/ui/backuprestore/backup_restore_page.dart` | M4 zip + legacy import |
| `lib/plugins/plugin_manager.dart` | M5 uninstall 语义 |
| `lib/plugins/plugin_model.dart` | M5 manifest 字段 |
| `lib/core/capability.dart` | M5 namespace 声明 |
| `lib/services/webdav_service.dart` | M4 补 uploadBytes |
| `lib/services/backup_service.dart` | M4 拆为 NamespaceBackupService + LegacyImporter |
| `lib/main.dart` | M2 初始化顺序：backend → migration → plugins |

## 7. 测试策略

- 契约测试 `test/repository_contract_test.dart`：同一套 case 跑 sqlite 与文件实现。
- 迁移黄金测试：fixture DB → 迁移 → 遍历比对文件树 / tree.json。
- 文件系统专项：`filename_policy_test`、`tree_store_test`、`reconcile_test`、`trash_test`、`snapshot_test`。
- 崩溃注入：单测预置 tmp / staging 残留，验证启动清理。
- UI：现有 widget 测试保持；新增重命名冲突、外部改动提示。

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| 迁移丢数据 | DB 改名留档 + 迁移前后计数 / 长度抽样 + 失败整体回滚 |
| 文件名跨端不一致 | NFC 归一化 + 大小写不敏感去重 + 长度 / 非法字符策略集中一处 |
| 大库扫描卡顿 | 列表只 list 单目录；全量扫描仅在启动 / 恢复 / 搜索时做，用索引 mtime 失效 |
| iCloud 冲突副本 | `reconcile` 识别 `xxx 2.md` / conflicted 命名，UI 提示保留两份，不自动合并 |
| tree.json 多端写冲突 | 单端单写 + 写前 mtime / etag 检查 + 冲突时以磁盘为基重建并备份旧 tree |
| 大改期间功能回归 | M0~M2 双实现并存，backend 开关可切回 sqlite |

## 9. 开工建议

先只做 M0。这一步不改任何用户可见行为，但会把 `NoteProvider` 与 `NoteDao` 的耦合切开；后续 M1 才能用契约测试证明「文件实现与旧实现等价」。M0 完成后建议再评审一次接口签名，再进 M1，避免返工。
