# 日志分析参考

日志常见格式：`[级别)YYYYMMDDHHMMSS.mmm module:line]:消息`。部分未校时日志显示 `202208011200xx`，需要结合文件名和相邻事件校准。

## 关键词

| 层级 | 关键词 | 含义与边界 |
|---|---|---|
| 重启 | `[reb]: normal reboot=>Cold Start Up` | 冷启动，可能是断电恢复 |
| 重启 | `normal reboot=> system WebUI` | WebUI 发起重启 |
| 重启 | `abnormal reboot=> system self-healing` | 自愈机制触发，继续查网络检测和重启前事件 |
| 重启 | `stop feed watchdog` / `Restarting system` | 受控重启序列 |
| 蜂窝 | `NetServiceStateChange] no service` | 蜂窝无服务，不等于重启 |
| 蜂窝 | `Hcsq [sysmode]=NR/LTE/NOSERVICE` | 当前制式；变化不等于换基站 |
| 蜂窝 | `AtChooseOperatorsExecute` | 自动选网或重新注册 |
| 蜂窝 | `CEREG` | 注册状态、TAC 和小区信息 |
| 拨号 | `DIALUP_STATE_DISCONNECTED` | 数据连接断开 |
| 拨号 | `AtpDialupConnectStart` | 开始重拨 |
| 拨号 | `ndisstat ipv4Status = 0/3/6` | 断开 / 已连接 / 连接中 |
| Modem | `No data from NAS` | NAS 查询未返回预期数据；可能涉及查询接口、模组控制通道或固件日志路径，必须与注册、拨号和业务状态联合判断 |
| MQTT | `wj_mqtt` / `WJMqttConnect` | 设备厂商云通道，不等于用户 MQTT 平台 |
| 闪存 | `jffs2_sum_write_data: Summary too big` | 常见非致命 JFFS2 警告，需结合其他错误判断 |

`not lock band` 只说明频段锁未启用，不能单独证明频段、小区或基站发生变化。

## 分析顺序

1. 收集问题时间、时区、平台上下线记录和用户现象。
2. 扫描 `kmsg.log` 与 `pstore/console-ramoops`，先排除重启。
3. 对齐 `sysmode`、`no service`、`CEREG`、拨号状态和重拨事件。
4. 最后对齐 MQTT/TCP 或业务平台事件，判断业务离线是结果还是独立故障。
5. 结论中列出能确认、不能确认和需要补采的数据。

先建立本次日志事实和反证，再匹配案例库，避免根据案例标题选择性取证。轮转日志可能重叠，关键词命中次数是物理记录数，不直接等于故障次数。

判断换小区或换基站至少需要连续的 PCI、EARFCN、ECI/Cell ID、TAC 等数据。只有 `sysmode`、信号等级或 `no service` 时，不得断言发生换基站。

设备型号和版本可搜索 `AT^VERSION:EXTU`、`EXTH`、`EXTS`。
