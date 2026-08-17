# CASE-003: 短时无服务后恢复

- 设备：IC5980 / CPE-MAX3
- 症状：短时断网，数秒后自动恢复，无重启
- 判断：日志支持蜂窝注册或小区选择短时不稳定，但缺少连续 PCI、EARFCN、ECI/Cell ID，不能确认换基站
- 证据：`no service`、`NetCreateResetCellTimer`、`SIG=[0]`，随后 `CEREG` 恢复、`SIG=[5]`、自动注册
- 建议：检查天线、馈线、SIM 卡座和供电；做单频段对照；复现时补采 `CEREG`、`COPS`、`HCSQ`、`LCACELL`、`MONSC`、`RRCSTAT`
- 边界：没有 PCI/Cell ID 证据时不建议永久锁小区
- 验证状态：未验证
- 日期：2026-08-03
