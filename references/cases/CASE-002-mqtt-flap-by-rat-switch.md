# CASE-002: MQTT 平台频繁离线（4G/5G 制式切换）

- 设备型号：IC5980 / CPE-MAX3-V4.x
- 固件版本：11.0.0.185(H72SP1C00)
- 症状：设备在 MQTT 物联网平台频繁上下线（间隔 30 秒-10 分钟），设备信号正常（5G RSRP=-84）
- 根因：设备在 5G(NR) 和 4G(LTE) 之间频繁切换（NSA 组网下 LTE 锚点不稳定）。每次制式切换导致底层 PDU session 重建，拨号状态回到 DIALUP_STATE_DISCONNECTED 再重连。TCP 长连接（MQTT）因此被强制断开，平台判定离线。
- 关键日志特征：
  - Hcsq [sysmode] 在 NR 和 LTE 之间来回变化（统计单日 LTE 出现次数 >100 通常意味着频繁切换）
  - 拨号断开与 sysmode 变化在同一时间窗口
  - AtpDialupConnectStart 出现在拨号重连时
  - not lock band 持续出现（频段锁未启用）
  - 平台 OFFLINE 时间与设备拨号断开时间对应
- 建议：
  1. 锁 4G 排除制式切换抖动，观察 24-48 小时
  2. 修正 ping_addr（从 127.0.0.1 改为外网地址），让设备能及时发现断网并重连
  3. 确认 MQTT keepalive 间隔 < 蜂窝 NAT 超时时间（通常 30-60 秒）
  4. 注意 wj_mqtt（厂商云）的连接失败是独立问题，不影响用户 MQTT 平台
- 验证状态：未验证（锁 4G 等建议尚未经用户确认是否有效）
- 日期：2026-08-13