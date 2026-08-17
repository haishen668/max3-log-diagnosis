---
name: max3-log-diagnosis
description: >-
  Decrypt and analyze Huawei/TD-Tech CPE-MAX3 and IC5980 diagnostic packages.
  Use for diagnose_enc.tar, device offline events, cellular registration or
  dial-up faults, MQTT disconnects, signal changes, reboot causes, system
  self-healing, dfx_common_new, and recurring cases that may match the bundled
  case library.
---

# Max3 日志诊断

## 解密

要求 PowerShell 7+。执行：

```powershell
pwsh -File "<skill-dir>/scripts/Decrypt-IC5980.ps1" "<诊断包>" [-OutDir "<输出目录>"]
```

脚本接受设备 `.zip`、`.tar` 或原始 `diagnose_enc.tar`，输出 `mobilelog`。不需要厂商 EXE、Python、7-Zip、系统 tar 命令或联网。

只有在解密失败、出现未知格式或需要核对兼容范围时，读取 [references/decryption-format.md](references/decryption-format.md)。

## 诊断

1. 确认用户报告时间、时区和现象。
2. 先查 [references/cases/](references/cases/) 是否有相似案例。
3. 按时间窗口读取 `log/`、`kernel/`、`pstore/` 和 `modem_log/`。
4. 依次核对重启原因、蜂窝注册/制式、拨号状态、MQTT 或业务连接。
5. 使用 [references/log-analysis.md](references/log-analysis.md) 的关键词解释日志。
6. 输出时间线、日志证据、结论置信度、其他可能性和设备侧建议。

不要把以下事件自动等同：

- `sysmode` 变化不等于换基站。
- `no service` 不等于设备重启。
- 平台 MQTT 离线不等于设备内置 `wj_mqtt` 失败。
- `self-healing` 说明重启机制，不单独证明最初断网原因。

无法从日志确认 PCI、EARFCN、ECI 或 Cell ID 变化时，明确写“无法确认换小区/换基站”。

## 证据规则

- 分开标注“日志事实”“推断”“建议”。
- 根因机制被确认，不代表建议方案已经有效。
- 只有用户明确反馈实际效果，才能标记“用户确认有效”或“用户确认无效”。
- 没有验证反馈时统一标记“未验证”，使用“建议尝试”。
- 不记录 IMEI、ICCID、SIM 号、账号、密钥、公网/内网 IP 等敏感信息。

## 案例更新

有新日志模式、明确根因或用户反馈时，先询问用户是否加入案例库。获得同意后：

1. 在 `references/cases/` 新建或更新对应 `CASE-NNN-*.md`。
2. 更新 [references/case-library.md](references/case-library.md) 索引。
3. 仅追加新案例或更新对应案例的验证状态，不覆盖其他案例。
4. 同步到 Git 时使用差异合并；案例保持一案例一文件。

如已安装 IMA skill，可在用户指定的共享知识库中搜索和同步去敏案例。不得硬编码个人知识库 ID 或凭证；上传前必须获得用户同意。
