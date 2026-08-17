# CASE-002: MQTT 离线伴随注册或制式状态变化

- 设备：IC5980 / CPE-MAX3，固件 `11.0.0.185(H72SP1C00)`
- 症状：物联网平台频繁上下线
- 观察：部分日志中平台离线与 NR/LTE/NOSERVICE 状态变化、拨号断开和重拨处于相近时间窗口
- 待验证假设：蜂窝注册或数据连接重建可能导致 MQTT 会话中断；仅凭制式字段变化不能确认因果
- 证据：`Hcsq [sysmode]`、`DIALUP_STATE_DISCONNECTED`、`AtpDialupConnectStart` 与平台 OFFLINE 时间相关
- 建议：先补采注册、小区和拨号状态；如需锁 4G，只做 24-48 小时限时对照，记录基线、离线次数和回退配置；同时检查 MQTT Keep Alive 和平台会话超时
- 边界：`wj_mqtt` 是厂商云通道；仅有 `sysmode` 变化不能证明换基站，也不能证明锁 4G 有效
- 验证状态：未验证
- 日期：2026-08-13
