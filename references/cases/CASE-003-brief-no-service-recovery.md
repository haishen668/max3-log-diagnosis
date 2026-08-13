# CASE-003: short LTE no-service recovery

- 设备型号：IC5980 / CPE-MAX3-V4.x
- 症状：设备偶发短时断网，数秒后自动恢复，无重启
- 根因：LTE 覆盖/小区选择短时不稳定，触发无服务后厂商恢复定时器启动，CEREG 重新获取注册和小区信息后恢复。不能确认为跳基站，缺少 EARFCN/PCI/ECI 连续对比。
- 关键日志特征：
  - NetServiceStateChange] no service
  - NetCreateResetCellTimer create reset cell timer
  - SIG=[0]
  - 数秒后 CEREG successfully got TAC/cell info, SIG=[5]
  - AtChooseOperatorsExecute auto register network
  - 目标窗口无 Kernel panic / OOM / 异常重启
- 建议：
  1. 检查天线接头、馈线、SIM 卡座、供电
  2. 单 LTE 频段对照测试 24-48 小时
  3. 每次复现时保存 AT+CEREG、AT+COPS、AT^HCSQ、AT^LCACELL、AT^MONSC、AT^RRCSTAT
  4. 不建议在无 PCI/Cell ID 时永久锁小区
- 验证状态：未验证（建议方案尚未经用户确认是否有效）
- 日期：2026-08-03