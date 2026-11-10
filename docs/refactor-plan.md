# NotePad 文件化改造方案（v2.1）

> 基于《架构设计方案（地基版）》评审结论修订
> 日期：2026-10-31
> 适用对象：当前 Flutter 工程（lib/ 下 sqflite 权威实现）
> 变更：备份 / 回收站改为**能力级接口**，各命名空间在自己的路径下闭环

## 0. 一句话结论

在现有工程上先加一层 `NotesRepository` 接缝，把 UI 与 SQLite 解耦；再实现文件存储内核；备份与回收站不再由全局服务包办，而是由每个能力注册自己的 `BackupPolicy` / `TrashPolicy`，宿主只提供格式契约、安全机制与聚合 UI。最后用一次性迁移器把旧库转成 vault。

## 1. 已锁定的决策

| # | 决策点 | 结论 | 理由 |
|---|---|---|---|
| D1 | 同步范围 | v2 只做单机 + 系统备份 + 手动/WebDAV zip；iCloud Drive 实时同步不在本期 | 原方案把「设备备份」误当「同步」；真同步要 ubiquity container，冲突处理成本完全不同 |
| D2 | 元数据权威 | 正文 md 保持纯净；`tree.json` 承载 id / 顺序 / 创建时间 / 标签 / 收藏 | iCloud 按文件同步，front matter 会污染正文；单一 sidecar 便于重建与迁移 |
| D3 | 标题来源 | 标题 = 文件名（去扩展名），文件夹名 = 目录名 | 避免 title 与 path 双份漂移，外部改名自动生效 |
| D4 | 附件 | `<nsRoot>/assets/<noteId>/`，正文用相对路径引用 | 不随文档改名失效；避免 dot 目录在 Files/SAF 中不可见 |
| D5 | 回收站 | **能力自管**：内容 + manifest 在 `<nsRoot>/.notepad/trash/`，宿主 `TrashCenter` 提供搬运/恢复机制 | 满足「每个插件在自己路径下闭环」；数据随命名空间一起搬移 |
| D6 | 注册表 | 权威在 `<vaultRoot>/.notepad/registry.json`，记录命名空间 + 驱动能力 + 状态 | 换机 / 恢复后仍能发现命名空间 |
| D7 | 索引 | `<appDataRoot>/namespaces/<nsId>/index/`，可随时删除重建，绝不存用户意图 | 索引是派生数据 |
| D8 | 插件 | 声明式能力包 + 资源包，无第三方动态代码 | Flutter / iOS 无法安全动态加载；现有 `PluginManifest` 已是声明式 |
| D9 | 笔记插件 | 内置但可「卸载」（= 停用能力），数据、registry、trash、backup 保留 | 满足原方案「可装可卸」 |
| D10 | 改造方式 | Repository 接缝 + 双实现灰度，不做大爆炸重写 | 现有 UI 与 DB 强耦合，直接替换风险高 |
| D11 | 备份 / 回收站归属 | **接口与策略归能力，容器格式与安全机制归宿主**；不做全局单一实现 | 能力自己决定收什么、排除什么、恢复后重建什么；宿主保证可救援与一致性 |
| D12 | 能力停用后的自救 | 备份包、回收站 manifest 由宿主定义，停用插件后 `BackupCenter` / `TrashCenter` 仍可操作其数据 | 声明式插件的实现仍在宿主内，不能因为入口关闭就变成数据孤岛 |

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
VaultStore / TreeStore / FilenamePolicy / VaultIndex
   ↓
TrashCenter / NamespaceBackupCenter / AppBackupCenter
   ↑ 策略来自
StorageCapability（notes / 将来 git / 文件阅读）
   ↓
StorageRoot (SandboxRoot；未来 SafRoot)
```

关键变化：`TrashService`、`BackupService` 不再是全局单例；它们是**宿主机制**，通过能力注册的 `TrashPolicy` / `BackupPolicy` 得到每个命名空间的策略。

### 2.2 磁盘布局

```
<vaultRoot>/                         # workspace 根：iOS Documents/Notepad ; Android files/Notepad
├─ .notepad/
│  ├─ registry.json                  # workspace 级注册表（权威）
│  └─ staging/                       # 恢复临时区（成功后清理）
│
├─ 工作/                             # ↓ 以下为 notes 命名空间根（v2 中 nsRoot == vaultRoot）
│  ├─ 周报.md
│  └─ 会议.md
├─ 日记.md
├─ assets/<noteId>/xxx.png
└─ .notepad/                         # notes 能力私有
   ├─ namespace.json                 # 自描述 marker：id / plugin / schema
   ├─ tree.json                      # id / 顺序 / 时间 / 标签 / 收藏
   ├─ trash/
   │  ├─ manifest.json
   │  └─ items/<id>/...              # 保留原相对结构
   └─ migration.json                 # 迁移记录（来源 hash / 时间 / 结果）

<appDataRoot>/                       # iOS Library/Application Support/Notepad ; Android 内部 files
├─ namespaces/
│  └─ notes/
│     ├─ index/notes_index.json      # 派生：path / title / mtime / size
│     ├─ backups/<ts>.zip            # 能力自有快照（不进快照、不进 vault）
│     └─ logs/
└─ staging/                          # 全局恢复暂存
```

- 用户数据 + 回收站随命名空间根走；索引、备份、日志属于「本机派生 / 运维数据」，放 appDataRoot 下按命名空间隔离。
- 若某能力坚持把快照放在自己根目录内，必须同时把 `backups/` 加入该能力的固定排除项，否则会递归膨胀。
- `Caches` 只放渲染 / 图片缓存。

### 2.3 平台注意事项（不落地的话「备份语义」是错的）

- iOS：`appDataRoot` 默认**会**进 iCloud 设备备份，需对 `index/`、`backups/`、`logs/`、`staging/` 设置 `NSURLIsExcludedFromBackupKey`（平台通道或现成插件实现）。`Documents` 只是设备备份范围，不是 iCloud Drive。
- Android：`allowBackup` 默认开，需用 `fullBackupContent` / `dataExtractionRules` 排除上述目录。
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

- `path` 相对 nsRoot；`order` 只在**同一父目录**内比较。
- 列目录只需 `list(目录)` + tree 顺序，不做全库扫描。
- 对账：磁盘新增 → 生成 id 入 tree；tree 有而磁盘无 → 标记 `missing`（UI 灰态，可丢弃）；外部改名视为删 + 增（v2 不做内容指纹追踪）。
- tree.json 丢失 / 损坏 → 全盘扫描重建，顺序按文件名自然排序，并写 `migration.json` 的 `rebuilt: true`；用户顺序丢失是已知代价。

### 3.2 文件名规则（`FilenamePolicy`）

- 非法字符 `\ / : * ? " < > |` 与换行 → `_`；首尾控制字符去掉。
- 统一 NFC；空标题 → `未命名`；长度按 UTF-8 255 字节截断（留后缀余量）。
- 同目录重名（大小写不敏感比较，兼容 APFS）自动加 ` (2)`。
- `.notepad`、`assets`、以 `.` 开头 保留为系统命名，用户不可用。

### 3.3 StorageRoot

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
- 预留 `SafRoot`（Android 外部树），不在本期。
- `NamespaceHandle` 是 `StorageRoot` 的**受限视图**：路径被限制在某个 nsRoot 内，不能跨命名空间；能力代码只拿得到 handle，拿不到裸路径。

### 3.4 注册表（NamespaceRegistry）

`<vaultRoot>/.notepad/registry.json`：

```json
{"schema":1,"namespaces":[
  {"id":"notes","pluginId":"builtin.notes","root":"","displayName":"笔记","schema":1,
   "state":"active","drivers":{"backup":true,"trash":true},"createdAt":1761800000000}
]}
```

- `root` 为空表示命名空间根就是 vaultRoot；未来外部根记录绝对路径 / URI，并带可用性校验。
- `state`: `active` / `disabled` / `missing`。
- 生命周期：`register` / `resolve` / `deactivate(pluginId)` / `activate(pluginId)` / `forget(namespaceId)`。
- 卸载插件 = `deactivate`，**不** `forget`；备份与回收站仍可 `resolve` 到已停用命名空间。
- `forget` 才真正移除记录；执行前必须清空 trash 且二次确认。

### 3.5 回收站（能力级）

**每个命名空间自己的 trash**：

```
<nsRoot>/.notepad/trash/
├─ manifest.json
└─ items/<id>/...
```

```json
// manifest.json（宿主定义的格式，能力只补充 metadata 字段）
{"schema":1,"entries":[
  {"id":"note-01","kind":"note","originalPath":"工作/周报.md","trashPath":"items/note-01/周报.md",
   "deletedAt":1761800000000,"metadata":{"title":"周报"}}
]}
```

```dart
abstract class TrashPolicy {
  /// false 表示该能力删除不可恢复（UI 需明确提示，不做假回收站）。
  bool get enabled;

  /// 搬运前收集额外元数据（如笔记标题、附件列表）。
  Future<Map<String, Object?>> metadataFor(String relativePath);

  /// 恢复成功后重建能力自己的派生数据（索引、缓存等）。
  Future<void> afterRestore(List<TrashEntry> entries);
}
```

分工：

- **能力**：是否启用回收站、要记录什么元数据、恢复后要重建什么。
- **宿主 `TrashCenter`**：整棵子树搬运、manifest 读写、原子移动、恢复时重建父目录、重名加后缀、清空、跨命名空间聚合。搬运逻辑集中一处，能力不得自行实现，避免行为不一致。

聚合 UI 用 `ScopedTrashEntry { namespaceId, displayName, entry }`，回收站页可按「全部 / 单个能力」分组。

### 3.6 备份（能力级）

**容器格式由宿主固定**（保证任何命名空间即使插件停用也能被恢复）：

```
notes-20261031-120000.zip
├─ manifest.json
└─ data/                      # nsRoot 内容（按排除项裁剪）
```

```json
{"schema":1,"kind":"namespace-backup","namespaceId":"notes","namespaceSchema":1,
 "pluginVersion":"1.0.0","appVersion":"1.0.0","createdAt":1761800000000,
 "excluded":["index","backups","logs"],
 "files":[{"path":"工作/周报.md","size":123,"sha256":"..."}]}
```

```dart
abstract class BackupPolicy {
  /// 相对 nsRoot 的排除项；与宿主固定排除项（tmp / staging / 日志）取并集。
  List<String> get excludePatterns;

  /// 快照前静默写入、暂停后台任务，避免拍到中间态。
  Future<void> quiesce();

  /// 快照结束（无论成功失败）后恢复。
  Future<void> resume();

  /// 恢复后重建索引 / 缓存 / 迁移标记。
  Future<void> afterRestore();

  /// 旧格式导入（v2 目前只有 notes 需要，迁移时由宿主调用）。
  Future<LegacyImportResult> importLegacy(LegacySource source);
}
```

分工：

- **能力**：排除项、静默钩子、恢复后动作、旧格式导入。
- **宿主**：创建 zip、manifest 与 sha256、原子落盘、保留策略、恢复 staging + 写锁 + 旧目录备份、失败回滚、列表 / 删除。

两级中心：

- `NamespaceBackupCenter`：单命名空间快照与恢复（`lib/services/backup_center.dart`）。
- `AppBackupCenter`：整机备份 = 每个命名空间一个子包 + 顶层 manifest；恢复按命名空间顺序执行并记录 journal，**不宣称跨命名空间原子**；失败时逐项报告并允许重试。

```json
// 整机备份 app-....npbackup.zip
{"schema":1,"kind":"app-backup","appVersion":"1.0.0","createdAt":...,
 "namespaces":[{"id":"notes","archive":"namespaces/notes.zip","schema":1}]}
```

存储位置：默认 `<appDataRoot>/namespaces/<nsId>/backups/`；手动导出走系统文件选择器，WebDAV 上传整机包（`WebDavService` 需补 `uploadBytes`），目录 `/NotePadBackup` 保留。旧 JSON 仅作为**导入**格式。

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
  Future<List<ScopedTrashEntry>> listTrash();
  Future<void> restore(List<String> ids);
  Future<void> purge(List<String> ids);
  Future<List<NotePadNode>> search(String keyword);
  Future<List<NotePadNode>> recent({int limit});
  Future<NoteStatistics> statistics();
  Future<void> replaceAll(List<NotePadNode> nodes, {String? stagingDir});
}
```

- 列表接口返回的节点**不带 body**；编辑器调用 `readBody` 再取。`NotePadNode.content` 字段过渡期保留但默认空。
- 所有写操作走 `VaultStore` 内部串行队列，避免并发写 tree.json。

### 3.8 能力注册接口（备份 / 回收站从这里接入）

```dart
abstract class StorageCapability {
  String get namespaceId;
  String get pluginId;
  NamespaceDescriptor get descriptor;

  /// null = 不参与备份（UI 隐藏入口）。
  BackupPolicy? get backupPolicy;

  /// null = 删除不可恢复（UI 明确警告）。
  TrashPolicy? get trashPolicy;
}
```

- `Capability`（现有 UI 能力接口）实现者同时提供 `StorageCapability`，启动时注册到 `NamespaceRegistry`。
- 将来 git 插件可以有自己的 `TrashPolicy`（例如软删除到 `stash/`）和 `BackupPolicy`（打包 repo bundle），宿主不用理解语义。
- 插件停用后 `StorageCapability` 的实现仍在宿主内（声明式模型），所以 trash / backup 仍可执行，只是入口不展示。

## 4. 旧数据迁移

### 4.1 触发

启动检测 `Documents/app_database.db` 存在，且 `.notepad/migration.json` 无成功记录 → 进入迁移页。

### 4.2 步骤（幂等、可重入）

1. 宿主读取旧 DB 生成 `LegacySource`（只读）：整表按 `parent_id` / `sort_order` 还原树，回收站节点单独归类。
2. 预检：标题清洗、重名、超长、emoji、NFC 冲突 → 生成冲突报告。
3. 建 vault；若已有 vault，则本次迁移落到 `<vaultRoot>/.notepad/staging/<ts>/` 后合并。
4. 调用 notes 能力的 `BackupPolicy.importLegacy`：文件夹 mkdir、文章原子写 md、`sort_order` → tree `order`、保留原 id / created / updated。
5. 回收站节点写入 `<nsRoot>/.notepad/trash/` + manifest。
6. 写 `tree.json` + `migration.json`（来源 hash、节点数、耗时）。
7. DB 改名 `app_database.db.migrated-<ts>`，**不删除**。
8. 抽样校验（节点数、body 长度、层级 depth）；不一致则整体失败，保留 DB 并回滚 vault。

### 4.3 旧 JSON 备份导入

复用 `BackupService.decodeBackup` 的节点数组 → 包装成 `LegacySource` → 走 4.2 的导入器 → 预览后替换。保留 `format: 1` 兼容。

### 4.4 回滚

- 设置项 `storage.backend`（`sqlite` / `files`）+ `migration.ts`。
- 迁移失败或用户回退 → 删除 `migration.json`、把 `.migrated-*` 改回 `.db`，UI 回到旧实现；`SqliteNotesRepository` 保留到下一个大版本再删。

## 5. 里程碑（按依赖顺序）

### M0 · 接缝与安全网（不改用户可见行为）

- 新增 `lib/data/notes_repository.dart`、`lib/data/sqlite_notes_repository.dart`；`NoteProvider` 构造函数注入；`statistics_page`、`recent_page`、`backup_restore_page` 去掉直接 `NoteDao()`。
- 接口契约测试：以现有 NoteDao 行为为基线。
- 验收：功能零变化；`flutter analyze` 无新增告警；契约测试全绿。

### M1 · 文件内核 + 能力驱动契约

- `lib/core/storage/{storage_root, namespace_handle, storage_capability, backup_policy, trash_policy}.dart`
- `lib/data/vault/{vault_store, folder_fs, filename_policy, tree_store}.dart`
- `lib/services/{namespace_registry, trash_center, backup_center, vault_index}.dart`
- notes 能力实现 `StorageCapability`（backup / trash 策略），`VaultNotesRepository` 实现同一套接口。
- 契约测试双跑（临时目录 fixture）；专项：重名、emoji、超长名、大小写冲突、崩溃遗留 tmp、tree 损坏重建、外部新增 / 删除 / 改名对账、trash 搬运 / 恢复 / 清空、单命名空间快照 / 恢复。
- 验收：同一套契约测试全绿；基准脚本下 10k 文件单层目录列表 < 200ms；命名空间边界测试（handle 越界必须失败）。

### M2 · 迁移与切换

- `lib/data/migration/legacy_sqlite_source.dart`、`legacy_json_importer.dart`；`lib/ui/migration/`。
- 设置开关与失败回滚；`main.dart` 按 backend 决定初始化路径。
- 验收：真实结构 fixture（嵌套 / 回收站 / 重名 / 空标题 / emoji）迁移后文件树与 tree.json 完全对应；重复执行幂等；注入磁盘满 / 权限失败可回滚。

### M3 · UI 对接

- `home_page`：列表 / 拖拽排序 / 重命名 / 移动。
- `editor_page`：懒加载正文 + 防抖自动保存 + 写失败提示。
- `search_page`：索引标题 + 按需读正文。`recent_page` / `statistics_page` 走 repository；`recyclebin_page` 换聚合 `ScopedTrashEntry`。
- 外部变更：前台恢复触发 `reconcile` + 刷新；编辑中的文件被外部改动 → 提示重载，不静默覆盖。
- 验收：手工矩阵（新建 / 改名 / 移动 / 拖拽 / 搜索 / 回收站 / 杀进程重开）+ 现有 widget 测试通过。

### M4 · 备份中心 / 回收站聚合 / 平台排除项

- 备份中心页：按命名空间列表、单命名空间快照、整机备份、恢复（staging + 写锁）、删除；WebDAV `uploadBytes`；自动备份改造；旧 JSON 导入入口。
- 回收站页：按能力分组、全部 / 单个命名空间视图、恢复 / 永久删除 / 清空；停用能力的条目显示来源标签。
- iOS / Android 备份排除配置（平台通道 + manifest 规则）。
- 验收：快照 → 改数据 → 恢复；恢复中途被杀可恢复；hash 校验失败可拒绝；停用笔记后仍能看到并恢复其 trash / backup。

### M5 · 能力 / 插件语义

- `PluginManifest` 增 `namespace`、`uninstallable`、`schema`；`PluginManager.uninstall` 改为「停用 + 保留记录」；内置笔记允许卸载。
- 笔记停用后首页不显示入口，但备份 / 回收站仍可操作；重装恢复入口。
- `Capability` 增 `namespaceId`，与 `StorageCapability` 对接。
- 验收：卸载笔记 → 数据零变化 → 备份 / trash 可用 → 重装恢复；`forget` 需双重确认且要求 trash 为空。

### M7 · 工作台能力底座（W1–W3，已落地）

M0–M5 解决「数据怎么存」；M7 解决「能力怎么长」：笔记不再是应用本体，而是工作台上的一个能力。

- W1：`lib/workbench/base` + `services`——`ResourceUri`、`FileSystemProvider` / 注册表、`CommandRegistry`、`when` 子句与上下文键、`ContributionRegistry`、`EditorRegistry`（按 scheme + 文件名模式 + 优先级解析）、`ExtensionHost`（激活事件 / 停用释放 / 失败隔离）、`Workbench`（标签 / 会话 / 工作区）、`QuickOpenService`。
- W2：`extensions/` 里的 core（通用命令、文本编辑器、欢迎页、资源管理器视图）、notes（`NotesFileSystemProvider` + Markdown 编辑器复用 `EditorPage`）、files（`ProjectFileSystemProvider`，项目增删同步）；内置插件 manifest 迁为声明式 `contributes`。
- W3：`WorkbenchPage`（宽屏三栏 / 窄屏抽屉）、资源管理器、标签条、命令面板、状态栏；`main.dart` 在「插件系统」开启时切换根界面。
- 验收：插件停用 → 命令 / 菜单 / 视图 / 编辑器 / 文件系统即时消失且相关标签关闭，数据不动；再启用 → 懒激活恢复；`widget` 与单元测试见 [workbench.md §10](./workbench.md)。
- 后续（W4/W5）：全文搜索视图、打开方式持久化、编辑器拆分、桌面快捷键细化、设置贡献点、git 能力。

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
| `lib/ui/recyclebin/recyclebin_page.dart` | M3/M4 换聚合 TrashCenter |
| `lib/ui/backuprestore/backup_restore_page.dart` | M4 备份中心（按命名空间 / 整机） |
| `lib/plugins/plugin_manager.dart` | M5 uninstall 语义 |
| `lib/plugins/plugin_model.dart` | M5 manifest 字段 |
| `lib/core/capability.dart` | M5 关联 `namespaceId` |
| `lib/services/webdav_service.dart` | M4 补 `uploadBytes` |
| `lib/services/backup_service.dart` | M4 拆为 `BackupCenter` + `LegacyImporter`，旧静态方法只留导入 |
| `lib/main.dart` | M2 初始化顺序：backend → migration → registry → capabilities |

新增（M1）：

| 文件 | 职责 |
|---|---|
| `lib/core/storage/storage_capability.dart` | 能力注册备份 / 回收站策略 |
| `lib/core/storage/backup_policy.dart` | 快照策略钩子 |
| `lib/core/storage/trash_policy.dart` | 回收站策略钩子 |
| `lib/core/storage/namespace_handle.dart` | 命名空间内受限读写 |
| `lib/services/trash_center.dart` | 搬运 / 恢复 / 清空 / 聚合 |
| `lib/services/backup_center.dart` | 单命名空间与整机快照 |
| `lib/services/namespace_registry.dart` | 注册表 |
| `lib/data/vault/*` | 文件存储内核 |

## 7. 测试策略

- 契约测试 `test/repository_contract_test.dart`：同一套 case 跑 sqlite 与文件实现。
- 驱动契约测试：给 notes 能力写一个 fake `TrashPolicy` / `BackupPolicy`，验证宿主在「策略缺失」「策略抛异常」「排除项为空」下的行为。
- 迁移黄金测试：fixture DB → 迁移 → 遍历比对文件树 / tree.json。
- 文件系统专项：`filename_policy_test`、`tree_store_test`、`reconcile_test`、`trash_center_test`、`backup_center_test`。
- 崩溃注入：单测预置 tmp / staging 残留，验证启动清理；恢复中断后重入。
- UI：现有 widget 测试保持；新增重命名冲突、外部改动提示、按能力分组的回收站。

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| 备份 / 回收站各写一套，行为漂移 | 搬运与打包机制只在宿主实现；能力只配置策略；契约测试覆盖所有策略分支 |
| 能力停用后无法解读自己的数据 | 容器格式与 manifest 由宿主定义（D12），策略实现仍在宿主内；禁止插件自定义不透明格式 |
| 整机备份跨命名空间不一致 | 明确不承诺全局原子；顺序执行 + journal + 逐命名空间报告，可单独重试 |
| 备份放回 vault 导致递归膨胀 | 默认放 appDataRoot；若能力坚持放根内，宿主强制加入排除项并校验 |
| 回收站分散后用户找不到入口 | 聚合 `ScopedTrashEntry` + 按能力分组 + 停用标签；设置页显示各命名空间占用 |
| 迁移丢数据 | DB 改名留档 + 迁移前后计数 / 长度抽样 + 失败整体回滚 |
| 文件名跨端不一致 | NFC 归一化 + 大小写不敏感去重 + 长度 / 非法字符策略集中一处 |
| 大库扫描卡顿 | 列表只 list 单目录；全量扫描仅在启动 / 恢复 / 搜索时做，用索引 mtime 失效 |
| iCloud 冲突副本 | `reconcile` 识别 `xxx 2.md` / conflicted 命名，UI 提示保留两份，不自动合并 |
| tree.json 多端写冲突 | 单端单写 + 写前 mtime / etag 检查 + 冲突时以磁盘为基重建并备份旧 tree |
| 大改期间功能回归 | M0~M2 双实现并存，backend 开关可切回 sqlite |

## 9. 开工建议

先只做 M0。这一步不改任何用户可见行为，但会把 `NoteProvider` 与 `NoteDao` 的耦合切开；M1 再把 `TrashPolicy` / `BackupPolicy` 契约和 notes 实现一起落，用契约测试证明「文件实现与旧实现等价」。M0 完成后建议再评审一次接口签名，再进 M1，避免返工。

## 10. 实现状态（2026-11-04）

> 依据 `lib/` 与 `test/` 的实际内容核对；「手工矩阵」类验收尚未在设备上逐项执行。

| 里程碑 | 代码状态 | 自动化验证 | 缺口 |
|---|---|---|---|
| M0 接缝 | 完成：`NotesRepository` + `SqliteNotesRepository`，`NoteProvider` 注入 | `repository_contract_test`（sqlite / vault 双跑） | — |
| M1 内核 | 完成：`StorageRoot` / `NamespaceHandle` / vault / tree / 文件名策略 / 索引 | `vault_repository_test`、`filename_policy_test`、`storage_boundary_test` | 缺 `tree_store_test`、`reconcile_test`、崩溃注入、10k 基准脚本 |
| M2 迁移 | 完成：`LegacyMigrator`、backend 开关与失败回退 | 无 | 缺迁移黄金测试（fixture 迁移 / 幂等 / 回滚） |
| M3 UI | 已对接：首页、编辑器、搜索、回收站、外部改动对账 | 无 widget 级覆盖 | 手工矩阵待执行 |
| M4 备份 / 回收站 | 已实现：`BackupCenter`、聚合回收站、WebDAV、数据健康页；Android `fullBackupContent` / `dataExtractionRules` 与 iOS `isExcludedFromBackup` 已配置 | 无 | 缺 `backup_center_test`（hash 失败 / zip slip / zip bomb / 中断重入）；`TrashCenter` 未独立拆出；平台排除项需真机验证 |
| M5 插件语义 | 已实现：manifest `namespace` / `uninstallable` / `schema`、内置笔记可卸载（= 停用）、启停状态跨重启保留、注册表启动对齐、`forget` 回收站非空拒绝、笔记停用后的能力首页 | `namespace_registry_test`、`plugin_model_test` | `forget` 暂无 UI 入口（仅 `removeProject` 内部使用） |
| 文件阅读 | 项目导入 / 浏览 / 更新 / 移除 / 另存为笔记已实现；工作台里以只读 `files.<id>` 资源呈现 | `workbench_page_test`（只读资源） | `ExternalOpenService`（系统打开方式 / 分享）待排期 |
| M7 工作台底座 | W1–W3 完成：资源 / 命令 / when / 贡献点 / 编辑器解析 / 扩展宿主 / 工作台外壳 / 命令面板 | `test/workbench/*`（单元 + widget，79 例） | 无设备端手工验证；W4 起（全文搜索、编辑器拆分、设置贡献点）待排期 |

**后续建议顺序**：补 `backup_center_test` 与迁移黄金测试（风险最高的两条数据路径）→ 补 tree / 对账 / 崩溃注入测试 → 拆出 `TrashCenter` → 清理 sqlite 实现（D10：保留至下一个大版本）。
