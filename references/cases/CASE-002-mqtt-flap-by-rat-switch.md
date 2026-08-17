# CASE-002: MQTT 离线与制式切换

- 设备：IC5980 / CPE-MAX3，固件 `11.0.0.185(H72SP1C00)`
- 症状：物联网平台频繁上下线
- 判断：若 NR/LTE 变化、拨号断开、重拨和平台离线处于同一时间窗口，制式变化引起的数据连接重建是高概率原因
- 证据：`Hcsq [sysmode]`、`DIALUP_STATE_DISCONNECTED`、`AtpDialupConnectStart` 与平台 OFFLINE 时间相关
- 建议：锁 4G 做 24-48 小时对照；按业务需要配置网络检测；检查 MQTT keepalive 和平台会话超时
- 边界：`wj_mqtt` 是厂商云通道；仅有 `sysmode` 变化不能证明换基站
- 验证状态：未验证
- 日期：2026-08-13
