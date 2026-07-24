# LookInside 真机端口检查脚本设计

## 目标

新增一个可重复运行的 macOS 命令行脚本，检查 USB 真机是否能被
LookInside 的连接链路识别，并验证真机上的 LookinServer 是否正在
`127.0.0.1:47175` 至 `127.0.0.1:47179` 中的某个端口监听。

脚本只执行诊断，不修改项目配置、不重启系统服务，也不改变设备状态。

## 文件与入口

- 主脚本：`Scripts/check-lookinside-device-port.sh`
- 测试脚本：`Tests/Scripts/check-lookinside-device-port-tests.sh`

默认用法：

```bash
Scripts/check-lookinside-device-port.sh
```

指定真机：

```bash
Scripts/check-lookinside-device-port.sh --udid 00008140-000D59423C0A801C
```

帮助：

```bash
Scripts/check-lookinside-device-port.sh --help
```

## 设备选择

脚本以 `idevice_id -l` 的结果作为 USB/usbmux 可通信设备的权威列表。

- 没有设备：失败并说明 CoreDevice 显示 connected 不代表 usbmux 已可用。
- 只有一台设备：自动选择。
- 有多台设备：失败并列出 UDID，要求使用 `--udid` 明确指定。
- 指定了 `--udid`：验证该 UDID 存在于 USB 设备列表中，否则失败。

脚本还会运行 `xcrun devicectl list devices` 并展示结果，作为 CoreDevice
层的辅助信息。该命令失败时记录警告，但不覆盖 `idevice_id` 的判断。

## 依赖检查

运行前检查：

- `xcrun`
- `idevice_id`
- `iproxy`
- `nc`

缺少 `idevice_id` 或 `iproxy` 时，提示通过 Homebrew 安装
`libimobiledevice` 和 `libusbmuxd`。缺少任意必要依赖时，不启动探测。

## 端口探测

真机端口固定为 `47175` 至 `47179`，与
`Sources/LookinServer/Shared/LookinDefines.h` 中的定义保持一致。

脚本为这五个端口建立临时本地映射。本地端口从 `58175` 开始；若端口已
被占用，脚本应在启动转发前失败并指出冲突端口，不结束或覆盖已有进程。

每个端口的探测流程为：

1. 通过 `iproxy` 将本地端口映射到指定真机端口。
2. 使用 `nc` 建立连接并短暂保持连接。
3. 若连接立即被真机拒绝，标记为 `CLOSED`。
4. 若连接保持成功，标记为 `OPEN`，随后主动结束探测连接。

探测结果逐行输出，例如：

```text
47175 OPEN
47176 CLOSED
47177 CLOSED
47178 CLOSED
47179 CLOSED
```

LookinServer 会占用该范围中的第一个可用端口，因此只有一个端口为
`OPEN` 是正常结果。脚本不要求监听端口必须是 `47175`。

## 清理与安全

脚本使用 `trap` 处理正常退出、错误退出、`SIGINT` 和 `SIGTERM`：

- 结束脚本创建的探测连接。
- 结束脚本创建的 `iproxy` 进程。
- 删除脚本创建的临时目录和日志。

脚本只终止自己记录的进程 ID，不使用 `pkill`，也不处理其他
`iproxy` 实例。探测会短暂占用 LookinServer 连接；连接结束后，
LookinServer 按现有实现自动恢复监听。

## 输出与退出状态

- 退出码 `0`：至少一个真机端口可连接。
- 退出码 `1`：设备不可用、依赖缺失、全部端口关闭、转发失败或参数错误。

成功摘要包含选中的 UDID 和所有端口结果。失败摘要指出故障所在层：
依赖、CoreDevice、usbmux、端口转发或 LookinServer 监听。

## 测试策略

测试通过临时 `PATH` 提供可控的命令替身，避免依赖真实 iPhone，同时执行
真实脚本入口和真实参数解析。覆盖：

1. 单台 USB 设备自动选择。
2. 多台设备时必须使用 `--udid`。
3. 指定不存在的 UDID 时失败。
4. 没有 USB 设备时失败。
5. 一个端口开放时成功并报告该端口。
6. 所有端口关闭时失败。
7. CoreDevice 查询失败时仅警告，继续使用 usbmux 结果。
8. 正常与异常退出后均不留下脚本创建的后台进程或临时文件。

实现遵循测试先行：先加入失败测试并确认失败原因，再实现满足该测试的最小
脚本行为，最后运行完整脚本测试集。

## 非目标

- 不验证 Lookin 协议层的 Ping、版本或许可证握手。
- 不读取或过滤目标 App 的设备日志。
- 不安装依赖。
- 不自动重启 CoreDevice、usbmuxd、Xcode 或目标 App。
- 不支持无线设备探测。
