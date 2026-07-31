# Dashboard 自定义属性说明与 Object ID 设计

## 背景

Dashboard 顶部已有“+”菜单和“如何添加自定义属性…”入口，但社区版当前只弹出“外链已禁用”的提示，用户无法从产品内获知 `lookin_customDebugInfos` 的接入方式。与此同时，MCP 的 `hierarchy.read` 会为每个层级节点返回 `objectIdentifier`，Dashboard 却没有展示同一标识，用户难以把界面中的对象与 MCP 调用参数对应起来。

## 目标

1. 让“如何添加自定义属性…”成为可用的本地说明入口，不依赖外部网站，并提供可复制的 Objective-C 接入示例。
2. 在 Dashboard 的 Class 卡片上方展示当前对象的 MCP Object ID，并提供一键复制。
3. UI 展示值与 MCP `hierarchy.read` 返回值由同一格式化实现产生，避免格式或对象选择规则漂移。

## 非目标

- 不新增“输入任意 KeyPath 并远程读写”的协议。
- 不改变 LookinServer 已有的 `lookin_customDebugInfos` 数据格式、Setter 传输协议或属性编辑机制。
- 不把 Object ID 当作跨 App 重启持久化的标识。
- 不在归档/只读文档里伪造可用于 MCP 的 Object ID。

## 方案比较

### 方案 A：内置说明与代码模板（采用）

点击菜单项后显示本地说明窗口，解释方法名、字典结构、支持类型及只读/可写属性，并提供完整示例与“复制代码”按钮。它直接对应仓库现有的 LookinServer 能力，离线可用且不需要扩展协议。

### 方案 B：恢复外部文档链接

开发量较小，但社区版当前明确禁用旧外链，文档可用性受网络和站点生命周期影响，也无法保证与当前源码同步。

### 方案 C：桌面端动态添加 KeyPath

交互直观，但需要定义新的查询、类型转换、Setter、安全限制和错误协议。它并非截图中“如何添加自定义属性…”入口所对应的既有模型，本次不采用。

## 自定义属性说明交互

- 保留现有 `+` 菜单和菜单文案。
- `LKDashboardHeaderView` 不直接构造业务说明；点击菜单项后通过 delegate 通知 `LKDashboardViewController`。
- Dashboard 创建一个独立的说明窗口控制器，避免把长代码模板和复制逻辑塞入 Header。
- 说明窗口包含：
  - 简短接入步骤；
  - `lookin_customDebugInfos` Objective-C 示例；
  - `title`、`section`、`valueType`、`value`、`retainedSetter` 字段说明；
  - 当前服务端支持的类型：`string`、`number`、`bool`、`color`、`rect`、`size`、`point`、`insets`、`shadow`、`enum`、`json`；
  - 只读属性与可编辑属性的区别；
  - “复制代码”和“完成”按钮。
- 代码区域使用等宽、只读、可选择的文本视图。复制成功后给出短暂的“已复制”反馈。
- 示例使用弱引用捕获对象，并同时包含字符串只读项和布尔可写项，确保用户能直接理解 Setter 的结构。

## Object ID 数据模型

MCP 当前使用：

```swift
let oid = item.displayingObject()?.oid ?? 0
String(format: "0x%lx", oid)
```

`displayingObject` 的选择顺序为 `windowObject`、`viewObject`、`layerObject`。UI 必须严格沿用该规则，不能使用选择顺序不同的 `bestObjectOidPreferView:`，也不能使用对象内存地址。

在客户端的 `LookinDisplayItem` 分类中增加共享格式化接口：

```objc
- (nullable NSString *)lk_mcpObjectIdentifier;
```

- `displayingObject.oid == 0` 时返回 `nil`。
- 其他情况返回带 `0x` 前缀的小写十六进制字符串。
- MCP lookup 和 Dashboard Object ID 行均调用该接口。

## Object ID 交互与布局

- 新增聚焦单一职责的 `LKDashboardObjectIDView`。
- 该 View 放入 `cardContainerView`，位于所有属性卡片之前，因此稳定显示在 Class 卡片上方。
- 外观使用与 Dashboard 卡片一致的圆角和动态背景：左侧标题 `Object ID`，中间等宽值，右侧复制图标按钮。
- 值文本允许点击复制，按钮 tooltip 为“复制 Object ID”。
- 复制写入系统剪贴板的文本必须与 MCP `hierarchy.read` 返回的 `objectIdentifier` 完全一致。
- 选择对象变化时，现有 Dashboard reload 链路同步更新该行。
- 搜索模式下随 `cardContainerView` 一起隐藏；退出搜索后恢复。
- 仅实时文档且 ID 有效时显示。只读/归档 Dashboard 或 OID 为 0 时不显示，不暴露不可用于 MCP 的值。

## 状态与错误处理

- 自定义属性说明完全来自本地常量，不存在网络失败状态。
- 剪贴板写入失败时不展示成功反馈；成功时短暂显示“已复制”。
- Object ID View 每次 render 都覆盖旧值，避免复用或对象切换后留下过期 ID。
- 说明窗口重复触发时复用或聚焦现有窗口，避免创建多个相同窗口。

## 文件边界

- `LookInside/Dashboard/Search/LKDashboardHeaderView.h/.m`：增加说明入口 delegate 事件。
- `LookInside/Dashboard/LKDashboardViewController.m`：响应说明入口、创建/更新 Object ID 行。
- `LookInside/Dashboard/LKCustomPropertyGuideWindowController.h/.m`：说明窗口、模板及复制反馈。
- `LookInside/Dashboard/LKDashboardObjectIDView.h/.m`：Object ID 展示和复制。
- `LookInside/Base/Category/LookinDisplayItem+LookinClient.h/.m`：共享 MCP Object ID 格式化接口。
- `LookInside/MCPBridge/LKMCPBridgeLiveDocumentLookup.swift`：改为调用共享接口。
- `LookInside.xcodeproj/project.pbxproj`：加入新源码文件。

## 验证策略

1. 先增加轻量源码行为测试，验证共享 formatter 被 MCP 和 Dashboard 同时使用、无效 OID 不显示、说明入口不再调用禁用外链提示、复制路径写入原始字符串。
2. 运行测试并确认在实现前失败。
3. 完成最小实现后重新运行测试。
4. 运行 `Scripts/test.sh`，覆盖 Swift Package 与 macOS App Debug 构建。
5. 启动 App 人工核对：菜单可打开说明、代码可复制、Object ID 位于 Class 上方、切换层级节点后值更新。
6. 对同一选中对象执行 MCP `hierarchy.read`，核对 UI 与返回的 `objectIdentifier` 完全一致。
