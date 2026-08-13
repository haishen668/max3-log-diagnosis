# CASE-001: 固件自愈重启（system self-healing）

- 设备型号：IC5980 / CPE-MAX3-V4.x
- 固件版本：11.0.0.185(H72SP1C00)
- 症状：设备不定期自动重启，业务全部中断，用户无感知原因
- 根因：固件/应用层触发的自愈重启策略。日志记录 abnormal reboot => system self-healing，pstore 有完整受控重启序列（self-healing → stop feed watchdog → Restarting system）。非断电、非内核 panic。具体触发条件需厂商提供原因码。
- 关键日志特征：
  - kmsg.log 首行：[reb]: abnormal reboot=> system self-healing
  - pstore/console-ramoops：[NNNN] self-healing → [WTD] reboot stop feed watchdog, event = 1 → reboot: Restarting system
  - 多个独立启动会话出现同一原因
- 建议：
  1. 向厂商提交诊断包，索要 self-healing 触发条件和原因码
  2. 核查 WebUI 的定时重启/健康检测配置，排除误配置
  3. 排查供电、散热
  4. 锁频段/锁小区无效，不能作为自愈重启的修复手段
- 验证状态：未验证（仅有日志诊断结论，未确认建议方案是否解决问题）
- 日期：2026-08-03