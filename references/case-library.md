# 案例库

> 这是技能的自我积累知识库。每次完成有价值的诊断并获得用户确认后，在此追加案例。
> 格式见 SKILL.md 的"自我更新机制"章节。

---

## CASE-001: 固件自愈重启（system self-healing）

- 设备型号：IC5980 / CPE-MAX3-V4.x
- 固件版本：11.0.0.185(H72SP1C00)
- 症状：设备不定期自动重启，业务全部中断，用户无感知原因
- 根因：固件/应用层触发的自愈重启策略。日志记录 abnormal reboot => system self-healing，pstore 有完整受控重启序列（self-healing → stop feed watchdog → Restarting system）。非断电、非内核 panic。具体触发条件需厂商提供原因码。
- 关键日志特征：
  - kmsg.log 首行：[reb]: abnormal reboot=> system self-healing
  - pstore/console-ramoops：[NNNN] self-healing → [WTD] reboot stop feed watchdog, event = 1 → reboot: Restarting system
  - 多个独立启动会话出现同一原因
- 解决方案：
  1. 向厂商提交诊断包，索要 self-healing 触发条件和原因码
  2. 核查 WebUI 的定时重启/健康检测配置，排除误配置
  3. 排查供电、散热
  4. 锁频段/锁小区无效，不能作为自愈重启的修复手段
- 确认状态：用户确认（基于 2 台设备的日志证据）
- 日期：2026-08-03

---

## CASE-002: MQTT 平台频繁离线（4G/5G 制式切换）

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
- 解决方案：
  1. 锁 4G 排除制式切换抖动，观察 24-48 小时
  2. 修正 ping_addr（从 127.0.0.1 改为外网地址），让设备能及时发现断网并重连
  3. 确认 MQTT keepalive 间隔 < 蜂窝 NAT 超时时间（通常 30-60 秒）
  4. 注意 wj_mqtt（厂商云）的连接失败是独立问题，不影响用户 MQTT 平台
- 确认状态：用户确认（日志证据链完整，含平台离线时间对照）
- 日期：2026-08-13

---

## CASE-003: 短时 LTE 无服务后自动恢复

- 设备型号：IC5980 / CPE-MAX3-V4.x
- 症状：设备偶发短时断网，数秒后自动恢复，无重启
- 根因：LTE 覆盖/小区选择短时不稳定，触发无服务 → 厂商恢复定时器 → CEREG 重新获取注册/小区信息 → 恢复。不能确认为"跳基站"（缺少 EARFCN/PCI/ECI 连续对比）。
- 关键日志特征：
  - NetServiceStateChange] no service
  - NetCreateResetCellTimer create reset cell timer
  - SIG=[0]（无信号）
  - 数秒后 CEREG successfully got TAC/cell info，SIG=[5]（恢复）
  - AtChooseOperatorsExecute auto register network
  - 目标窗口无 Kernel panic / OOM / 异常重启记录
- 解决方案：
  1. 检查天线接头、馈线、SIM 卡座、供电
  2. 单 LTE 频段对照测试 24-48 小时
  3. 每次复现时保存 AT+CEREG?、AT+COPS?、AT^HCSQ?、AT^LCACELL?、AT^MONSC?、AT^RRCSTAT?
  4. 不建议在无 PCI/Cell ID 时永久锁小区
- 确认状态：用户确认
- 日期：2026-08-03
