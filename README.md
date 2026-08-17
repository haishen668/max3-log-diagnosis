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

## 内容

- `SKILL.md`：Agent 诊断流程
- `scripts/Decrypt-IC5980.ps1`：纯 .NET 解密与安全解包
- `references/log-analysis.md`：日志关键词和判断规则
- `references/cases/`：一案例一文件的案例库
- `references/decryption-format.md`：容器格式和验证边界

真实格式版本 1 已与厂商工具逐文件 SHA-256 对比一致；格式版本 3 目前只有协议级合成测试。案例中的处理建议必须按各文件的验证状态表述，不能把未验证方案写成确定有效。
