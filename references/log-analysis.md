# IC5980 日志分析参考

## 时间戳格式

`[级别)YYYYMMDDHHMMSS.mmm module:line]:消息`

- 级别：I=Info, E=Error, W=Warning
- 例：`[E)20260813101309.754 net:499]:[NetServiceStateChange] not lock band`
- 注意：未校时的日志显示 202208011200xx，以文件名为准

## 关键日志术语与 grep 模式

### 重启与自愈

| 日志关键词 | 含义 | grep 模式 |
|---|---|---|
| `[reb]: normal reboot=>Cold Start Up` | 正常冷启动（断电恢复） | `\[reb\]:` |
| `[reb]: normal reboot=> system WebUI` | WebUI 触发的正常重启 | `\[reb\]:` |
| `[reb]: abnormal reboot=> system self-healing` | 固件自愈重启（需查原因码） | `abnormal reboot|self-healing` |
| `[WTD]: reboot stop feed watchdog` | 受控看门狗辅助重启 | `stop feed watchdog` |
| `reboot: Restarting system` | 系统重启完成 | `Restarting system` |
| `system power on ok!` | 开机完成 | `power on ok` |

### 网络与信号

| 日志关键词 | 含义 | grep 模式 |
|---|---|---|
| `NetServiceStateChange] no service` | 蜂窝无服务 | `NetServiceStateChange\] no service` |
| `NetServiceStateChange] not lock band` | LTE 频段锁未启用（正常日志，高频出现） | `not lock band` |
| `NetCreateResetCellTimer` | 厂商恢复定时器启动 | `NetCreateResetCellTimer` |
| `Hcsq [sysmode]=NR` | 当前 5G NR 模式 | `Hcsq \[sysmode\]` |
| `Hcsq [sysmode]=LTE` | 当前 4G LTE 模式 | `Hcsq \[sysmode\]` |
| `Hcsq [sysmode]=NOSERVICE` | 无服务模式 | `sysmode\]=NOSERVICE` |
| `SIG=[0]` / `SIG=[5]` | 厂商内部信号等级（非标准 RSRP） | `SIG=\[` |
| `AtChooseOperatorsExecute` | 自动选网/注册 | `AtChooseOperatorsExecute` |

### 拨号与数据连接

| 日志关键词 | 含义 | grep 模式 |
|---|---|---|
| `DIALUP_STATE_DISCONNECTED` | 拨号断开 | `DIALUP_STATE` |
| `AtpDialupConnectStart` | 拨号开始 | `AtpDialupConnectStart` |
| `ndisstat ipv4Status = 3` | IPv4 数据连接已建立（状态 3=已连接） | `ndisstat` |
| `ndisstat ipv4Status = 0` | IPv4 数据连接断开 | `ndisstat` |
| `ndisstat ipv4Status = 6` | 正在连接中 | `ndisstat` |
| `DialupConfigGetIndexByKeyListFromDb error` | APN/拨号配置数据库查询失败 | `DialupConfigGetIndexByKeyListFromDb.*error` |
| `AtReadCmdNas] No data from NAS` | 主控向 Modem 查询 NAS 状态无响应 | `No data from NAS` |

### MQTT 与云连接

| 日志关键词 | 含义 | grep 模式 |
|---|---|---|
| `wj_mqtt: Failed to start connect` | 设备内置 MQTT（WujiMax3）连接失败 | `wj_mqtt` |
| `wj_mqtt: Failed to WJMqttConnect` | WujiMax3 云连接失败 | `wj_mqtt` |
| `WujiMax3Init: WJMqttLoadConfiguration failed` | MQTT 配置加载失败 | `WujiMax3Init|WJMqttLoadConfig` |

注意：wj_mqtt 是设备厂商云连接，与用户自有 MQTT 平台是独立通道。

### 闪存与文件系统

| 日志关键词 | 含义 | grep 模式 |
|---|---|---|
| `jffs2_sum_write_data: Summary too big` | JFFS2 摘要区容量警告（Linux 源码标注 Non-fatal） | `Summary too big` |

## 常见分析场景

### 场景一：设备频繁离线

1. 统计 sysmode 变化：NR->LTE 或 LTE->NOSERVICE 的频率
2. 统计 DIALUP_STATE_DISCONNECTED 出现次数和时间
3. 检查 sysmode 变化是否与拨号断开时间对应
4. 检查 ping_addr 配置（127.0.0.1 表示连通性检测无效）

### 场景二：设备异常重启

1. 扫描所有 kmsg.log 的 [reb] 行，列出重启原因
2. 检查 pstore/console-ramoops 是否有 self-healing 序列
3. 区分：Cold Start Up=断电、WebUI=人为重启、self-healing=固件自愈
4. self-healing 的根因需要厂商提供原因码

### 场景三：网络信号问题

1. 提取 Hcsq [sysmode] 和 value1（参考信号强度）的时间序列
2. 统计 no service 事件持续时长
3. 检查 not lock band 是否伴随频段/小区变化
4. 对比问题时间点的 RSRP/RSRQ/SINR 值

## 设备型号识别

从 app.log 或 kmsg.log 读取：
- AT^VERSION:EXTU:IC5980（设备型号）
- AT^VERSION:EXTH:CPE-MAX3-V4.x Ver.A（硬件版本）
- AT^VERSION:EXTS:11.0.0.185(H72SP1C00)（软件/WebUI 版本）
