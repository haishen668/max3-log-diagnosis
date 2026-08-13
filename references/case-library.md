# 案例索引

每个案例是一个独立文件，存放在 cases/ 子目录，文件名格式 CASE-NNN-描述.md。

这种结构让案例库可以通过 git 仓库更新（pull）时自动合并：新增案例 = 新增文件，不会与其他人的修改冲突。只需要 pull 后重新列出 cases/ 目录即可。

## 当前案例

- [CASE-001 固件自愈重启](cases/CASE-001-self-healing-reboot.md)
- [CASE-002 MQTT 频繁离线（4G/5G 切换）](cases/CASE-002-mqtt-flap-by-rat-switch.md)
- [CASE-003 短时无服务后自动恢复](cases/CASE-003-brief-no-service-recovery.md)

## 验证状态说明

所有案例当前均为未验证：诊断结论有日志证据支撑，但建议的解决方案尚未经用户在设备上确认是否有效。AI 在引用这些案例时，应明确说明这是待验证的建议，而非已确认的修复。