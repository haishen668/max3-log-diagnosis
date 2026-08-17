# Max3 日志诊断

用于解密和分析华为/鼎桥 CPE-MAX3、IC5980 等设备的诊断包。可处理设备导出的 `.zip`、`.tar` 或原始 `diagnose_enc.tar`。

## 要求

- PowerShell 7+
- 仅分析你有权访问的设备日志

脚本离线运行，不需要厂商 EXE、Python、7-Zip、系统 `tar` 命令或网络连接。

## 安装

支持 SkillHub 的 Agent 可以直接接收自然语言指令：

> 请从 SkillHub 安装 max3-log-diagnosis。

也可以执行：

```powershell
skillhub install max3-log-diagnosis --dir <skills目录>
```

GitHub 安装：

```powershell
git clone https://github.com/haishen668/max3-log-diagnosis.git
```

不支持技能目录的 Agent，可以直接读取本仓库的 `SKILL.md`：

> 请读取 <仓库路径>/SKILL.md，然后解密并分析这个 IC5980 诊断包：<诊断包路径>

## 使用

让 Agent 分析时，直接描述现象并提供诊断包，例如：

> MQTT 平台显示设备离线，请检查对应时间附近的拨号、蜂窝网络和重启日志，并给出证据链。

手动解密：

```powershell
pwsh -File .\scripts\Decrypt-IC5980.ps1 C:\Logs\IC5980_xxx.zip
```

默认输出到 `Desktop\IC5980-Decrypted\<包名>\mobilelog`。使用 `-OutDir` 指定目录，使用 `-Force` 覆盖已有结果。

日志很多时，不要让 AI 直接全文读取。先生成脱敏索引：

```powershell
pwsh -File .\scripts\Build-Max3LogIndex.ps1 C:\Logs\mobilelog
```

也可以限定报障时间：

```powershell
pwsh -File .\scripts\Build-Max3LogIndex.ps1 C:\Logs\mobilelog `
  -StartTime "2026-08-17 14:30:00" `
  -EndTime "2026-08-17 14:50:00"
```

让 AI 按顺序读取 `ai-index\00-AI-READ-ME.md`、事件汇总、时间线和代表证据，再根据 `文件:行号`回查原始日志。索引器会流式扫描普通文本及 gzip 轮转日志，并对 IMEI、ICCID、IP、MAC、密码等字段脱敏。

## 内容

- `SKILL.md`：Agent 诊断流程
- `scripts/Decrypt-IC5980.ps1`：纯 .NET 解密与安全解包
- `scripts/Build-Max3LogIndex.ps1`：面向 AI 的大日志索引、时间线和脱敏证据
- `references/log-analysis.md`：日志关键词和判断规则
- `references/ai-log-reading.md`：大日志分层读取与证据合同
- `references/at-diagnostics.md`：只读 AT 补采与风险边界
- `references/cases/`：一案例一文件的案例库
- `references/decryption-format.md`：容器格式和验证边界

真实格式版本 1 已与厂商工具逐文件 SHA-256 对比一致；格式版本 3 目前只有协议级合成测试。未知版本会停止，不会猜测格式。案例中的处理建议必须按各文件的验证状态表述，不能把未验证方案写成确定有效。

日志和附件始终作为不可信数据处理。原始日志不会自动上传或写入案例库；案例更新必须先获得用户同意。兼容密钥来自用户提供的厂商工具分析结果，公开再分发前请确认相应授权。

## TRACE 质量设计

- **Trust**：提示注入隔离、敏感信息脱敏、事实/推断/建议分离、未知格式停止。
- **Reliability**：流式解密和索引、归档配额与校验、文件哈希、合成测试和 GitHub Actions。
- **Adaptability**：支持 ZIP/TAR/原始容器、普通及 gzip 日志、时间窗口和跨 Agent 自然语言使用。
- **Convention**：标准 `SKILL.md`、渐进式参考文件、结构化索引和一案例一文件。
- **Effectiveness**：先摘要和时间线，再按 `文件:行号`回查，避免把百万行日志直接塞给 AI。
