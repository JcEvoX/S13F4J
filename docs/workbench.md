# NotePad 工作台（Workbench）能力底座设计

> 版本：v0.1（草案，随实现迭代）
> 日期：2026-11-04
> 关联文档：[product.md](./product.md) · [architecture.md](./architecture.md) · [refactor-plan.md](./refactor-plan.md)

## 1. 为什么需要这一层

此前的结构是「笔记应用 + 一个叫插件的开关」：首页、编辑器、回收站都直接写死为笔记，
插件只能整页 `launch` 一个独立页面，彼此没有共同语言。要成为「可装可卸能力的轻量 IDE」，
缺的不是更多页面，而是 VS Code 那样的**能力底座**：

| VS Code 概念 | 本项目对应 | 作用 |
|---|---|---|
| Workspace / URI / FileSystemProvider | `ResourceUri` + `FileSystemProvider`（每个命名空间一个） | 笔记、导入项目、将来的 git 工作区用同一套「资源」模型 |
| Command / Command Palette | `CommandRegistry` + 命令面板（`>` 命令，无前缀 = 快速打开文件） | 所有操作都是命令，能力通过命令互相调用 |
| Context key / `when` 子句 | `ContextKeyService` + `WhenClause` | 菜单、视图、命令的可见性与可用性由上下文决定 |
| Contribution Points | 插件 manifest 的 `contributes` | 声明式扩展工作台（命令、菜单、视图、编辑器、状态栏） |
| Custom Editor / Editor Resolver | `EditorRegistry`（按文件名模式 + 优先级选编辑器） | `.md` → Markdown 编辑器，其余文本 → 通用文本编辑器 |
| Extension Host / Activation Events | `ExtensionHost`（懒激活、停用即释放） | 能力按需启动，停用后命令 / 视图 / 文件系统全部注销 |
| Workbench（活动栏 / 侧栏 / 编辑区 / 状态栏） | `WorkbenchPage` | 统一外壳；窄屏自动退化为抽屉 + 标签条 |

**不变的约束**：D8 声明式插件（无第三方动态代码）。能力实现随宿主分发（`HostExtension`），
插件包只带 manifest 与资源；manifest 还可用 `run` 把宿主命令组合成宏，因此纯 JSON 插件也能「做事」。

## 2. 分层与依赖规则

```
lib/workbench/
├─ base/        Disposable · ResourceUri · WhenClause · ContextKeyService   （纯 Dart，无 Flutter）
├─ services/    CommandRegistry · FileSystemRegistry · ContributionRegistry
│               EditorRegistry · ExtensionHost · Workbench（编辑器分组 / 会话 / 工作区）
│               QuickOpen · WorkspaceSearch
├─ extensions/  core（通用命令 + 文本编辑器 + 欢迎页）· notes · files   （宿主内置能力）
└─ ui/          WorkbenchPage · 活动栏 · 资源管理器 · 标签条 · 命令面板 · 状态栏
```

- `base/`、`services/` 不依赖 `ui/`；`services/` 可依赖 `core/storage` 与 `data/`，反向禁止。
- `plugins/` 只存数据（manifest 的 `contributes` / `activationEvents` 原样保存），**不依赖** `workbench/`。
- 能力只能通过 `ExtensionContext` 注册贡献，拿不到注册表本体；所有注册返回 `Disposable`，
  停用时由宿主统一释放。
- 笔记 / 项目的数据路径不变：仍由 `NotesRepository`、`ProjectStore`、`BackupCenter` 负责，
  `FileSystemProvider` 只是它们面向工作台的适配层。

## 3. 资源与文件系统

### 3.1 ResourceUri

```
<namespaceId>:/<相对路径>      notes:/工作/周报.md      files.p-01:/lib/main.dart
```

- scheme 就是命名空间 id（与 `registry.json` 一致），因此「工作区文件夹」= 活动状态的命名空间。
- 路径规范化：以 `/` 开头、无尾部 `/`（根为 `/`）、拒绝 `..` 与空片段。

### 3.2 FileSystemProvider

读：`stat` · `readDirectory` · `readText`；写：`writeText` · `createFile` · `createDirectory` ·
`rename` · `delete`。默认实现的写操作抛 `E-READONLY`，只读能力（文件阅读项目）无需实现。
变更通过 `onDidChange` 广播父目录，资源管理器据此刷新。

| scheme | 实现 | 写能力 |
|---|---|---|
| `notes` | `NotesFileSystemProvider`（经 `NotesRepository`，保持 tree 顺序；删除 = 进回收站） | 读写 |
| `files.<projectId>` | `ProjectFileSystemProvider`（经 `ProjectStore`，只读，大小 / 二进制由宿主判定） | 只读 |

## 4. 命令、上下文与 when 子句

- 命令 = `id` + 元数据（标题 / 分类 / `when`）+ 处理函数（`CommandContext`：`workbench` + `args`）。
- 元数据来自 manifest；处理函数由 `HostExtension.activate` 注册，或由 manifest 的 `run` 宏提供。
- 执行一个尚未注册处理函数的命令会触发 `onCommand:<id>` 激活事件，再重试一次。
- `when` 语法：`key` · `!expr` · `a && b` · `a || b` · `key == 'v'` · `key != v` · 括号。
- 标准上下文键：`resourceScheme` / `resourceFilename` / `resourceExtname` / `resourceReadOnly`（活动编辑器）、
  `explorerResourceScheme` / `explorerResourceIsFolder` / `explorerResourceIsRoot`（资源管理器选中项）、
  `editorViewType`、`sidebarVisible`、`workspaceFolderCount`。

## 5. 贡献点（manifest `contributes`）

```jsonc
{
  "activationEvents": ["onStartup", "onCommand:notes.newNote", "onResource:notes", "onEditor:notes.markdown"],
  "contributes": {
    "commands": [
      { "command": "notes.newNote", "title": "新建笔记", "category": "笔记", "when": "workspaceFolderCount > 0" },
      { "command": "daily.today", "title": "今日笔记",
        "run": [ { "command": "notes.newNote", "args": ["notes:/", "今日.md"] } ] }
    ],
    "menus": {
      "commandPalette":  [ { "command": "notes.newNote" } ],
      "explorer/context": [ { "command": "notes.rename", "when": "explorerResourceScheme == notes && !explorerResourceIsRoot", "group": "2_modify" } ],
      "editor/title":    [ { "command": "notes.preview", "when": "resourceScheme == notes" } ]
    },
    "viewsContainers": { "activitybar": [ { "id": "search", "title": "搜索", "icon": "search" } ] },
    "views": { "explorer": [ { "id": "explorer.workspace", "name": "工作区" } ] },
    "editors": [ { "viewType": "notes.markdown", "displayName": "Markdown", "priority": "default",
                   "selector": [ { "scheme": "notes", "filenamePattern": "*.md" } ] } ],
    "statusBar": [ { "id": "notes.count", "text": "笔记", "command": "workbench.action.quickOpen", "alignment": "left" } ]
  }
}
```

- 声明（manifest）与实现（`HostExtension`）分离：未声明的命令不会出现在面板 / 菜单；已声明但无实现且无 `run`
  的命令在执行时给出明确错误，不静默失败。
- 贡献随插件启停生效：插件停用 → 该插件的命令 / 菜单 / 视图 / 编辑器 / 状态栏项立即从工作台消失，
  数据与命名空间保持不变（D9 / D12）。

### 编辑器解析

候选 = 已启用插件声明的 `editors`，按 `selector`（scheme + 文件名模式）匹配；
优先级 `default` > `option`，同级时更具体的选择器优先；无匹配回退内置 `workbench.text`
（只读由 provider 决定）。「打开方式…」可手动指定任一候选。

## 6. 扩展宿主与激活

```dart
abstract class HostExtension {
  FutureOr<void> activate(ExtensionContext context);
  FutureOr<void> deactivate() {}
}
```

- `ExtensionContext` 提供：`registerCommand` · `registerFileSystemProvider` · `registerEditorProvider` ·
  `registerViewProvider` · `setContext`，均返回 `Disposable` 并自动进入 `subscriptions`。
- 激活事件：`onStartup`（含 `*`）· `onCommand:<id>` · `onResource:<scheme>`（支持末尾 `*`）·
  `onEditor:<viewType>` · `onView:<viewId>`。
- 停用 / 卸载：释放 `subscriptions`、调用 `deactivate`、移除该插件的全部声明；再启用后重新按事件激活。
- 宿主内置的 `workbench.core`（通用命令、文本编辑器、欢迎页）不是插件，始终可用。

## 7. 工作台外壳

| 区域 | 宽屏（≥ 840dp） | 窄屏 |
|---|---|---|
| 活动栏 | 左侧常驻图标列（资源管理器 / 搜索 / 贡献的容器 / 插件中心 / 设置） | 抽屉内的图标列 |
| 侧栏 | 活动栏右侧，显示当前容器的视图 | 抽屉 |
| 编辑区 | 标签条 + 当前编辑器；标签懒构建、切换保活 | 同左 |
| 状态栏 | 底部：活动资源路径 / 只读标记 / 贡献的状态栏项 | 同左（单行） |
| 命令面板 | 顶部浮层：`>` 命令；无前缀按文件名快速打开；空输入显示最近文件 | 底部弹层 |

会话（打开的标签与活动标签、最近文件）持久化，重启后恢复；资源已不存在的标签保留并显示明确提示。

### 产品形态映射

- 插件系统**关闭**（默认）：保持「笔记形态」，首页即文件列表，不出现工作台概念。
- 插件系统**开启**：根界面切换为工作台；笔记只是其中一个能力（`builtin.notes`），可停用，
  停用后资源管理器不再出现 `notes` 根，备份 / 回收站入口仍可从命令面板与活动栏访问。

## 8. 与既有设计的衔接

| 既有机制 | 在工作台中的角色 |
|---|---|
| `NamespaceRegistry` | 工作区文件夹的来源（`state=active` 的命名空间）；停用 / 缺失态在资源管理器中灰显 |
| `StorageCapability`（备份 / 回收站策略） | 不变；工作台命令 `notes.openRecycleBin` / `workbench.action.openBackup` 只是入口 |
| `PluginManager` | 启停事件驱动 `ExtensionHost` 同步；`onPluginStateChanged` 仍同步命名空间状态 |
| `Capability.launch`（旧） | 保留，供旧入口使用；新能力通过 `HostExtension` 接入 |

## 9. 里程碑

| 阶段 | 内容 | 状态 |
|---|---|---|
| W1 | `base/` + `services/`（URI / 命令 / when / 文件系统 / 贡献 / 编辑器 / 宿主 / 工作台状态）与单元测试 | 本期 |
| W2 | `extensions/`（core / notes / files）+ manifest `contributes` 解析 + 内置插件迁移 | 本期 |
| W3 | `ui/` 工作台外壳（活动栏 / 资源管理器 / 标签 / 面板 / 状态栏）+ 根界面切换 + widget 测试 | 本期 |
| W4 | 全文搜索视图、打开方式、编辑器拆分、键盘快捷键（桌面）、设置贡献点 | 后续 |
| W5 | git 能力（独立命名空间 + `FileSystemProvider` + SCM 视图）| 后续 |
