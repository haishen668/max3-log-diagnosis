---
name: max3-log-diagnosis
description: >-
  Decrypt and analyze diagnostic logs from Huawei/TD-Tech CPE-MAX3 series devices
  (IC5980 and similar models). Covers encrypted package decryption (diagnose_enc.tar
  via dfx_common_new.exe), network/dialup/MQTT/reboot anomaly analysis, and
  self-improving case accumulation. Use when the user provides an IC5980/MAX3
  diagnostic .zip/.tar and asks to analyze device issues, investigate offline events,
  crashes, signal problems, or read device logs. Also use when the user mentions
  diagnose_enc.tar, dfx_common_new, wj_mqtt, system self-healing, CPE-MAX3, or asks
  about a recurring device issue that may match a known case.
---

# Max3 日志诊断

## 能力范围

解密 IC5980 / CPE-MAX3 系列设备的加密诊断包，分析设备侧日志中的网络、拨号、MQTT、重启异常，并从实际案例中持续学习。

## 解密流程

IC5980 诊断包是加密的（diagnose_enc.tar），无法直接读取。使用自带脚本：

```powershell
.${skill_dir}\scripts\Decrypt-IC5980.ps1 '<诊断包路径>' [-OutDir '<输出目录>']
```

脚本自动：判断格式（tar/zip）→ 提取 diagnose_enc.tar → 调用 dfx_common_new.exe 解密 → 输出明文日志。

解密后日志结构（mobilelog 目录下）：log/（应用日志）、kernel/（内核日志）、pstore/（重启记录）、modem_log/（基带日志）。

## 日志分析方法

### 读取 gzip 日志（PowerShell）

```powershell
$stream = [IO.File]::OpenRead($file)
$gzip = [IO.Compression.GzipStream]::new($stream, [IO.Compression.CompressionMode]::Decompress)
$reader = [IO.StreamReader]::new($gzip)
$text = $reader.ReadToEnd()
$reader.Dispose(); $gzip.Dispose(); $stream.Dispose()
```

### 分析策略

1. 先定位时间窗口：用户报告的问题时间 → 找对应 app.log 文件
2. 先看重启原因：扫描所有 kmsg.log 的 [reb] 行，区分 normal reboot vs self-healing
3. 再看网络异常：no service、DIALUP_STATE_DISCONNECTED、sysmode 变化
4. 最后看业务层：MQTT 连接、拨号状态、AT 命令

术语映射表和 grep 关键词见 [references/log-analysis.md](references/log-analysis.md)。

## 已知案例库

分析前，先查 [references/case-library.md](references/case-library.md) 是否有匹配的已知案例。这能避免重复诊断，并为用户提供经过验证的解决方案。

## 自我更新机制（重要）

每次完成一次有价值的诊断后，执行以下流程：

### 何时触发

满足以下任一条件：
- 诊断出了明确的根因和解决方案
- 发现了新的日志模式或异常类型
- 用户确认分析结论正确
- 遇到了 case-library.md 中未记录的新场景

### 更新流程

1. **完成诊断后**，向用户提问：
   - "这次分析结论对你有帮助吗？"
   - "这个问题是否之前在其他设备上也出现过？"
   - "你是否愿意把这个案例加入技能库，方便以后遇到同类问题时快速诊断？"

2. **仅在获得用户明确同意后**，将案例追加到 [references/case-library.md](references/case-library.md)。格式：

```markdown
### CASE-NNN: <简短标题>

- 设备型号 / 固件版本
- 症状：<用户报告的现象>
- 根因：<日志证据支撑的结论>
- 关键日志特征：<可 grep 的关键词和时间模式>
- 解决方案：<实际有效的处理步骤>
- 确认状态：<用户确认 / 已验证 / 待验证>
- 日期：<YYYY-MM-DD>
```

3. **同时更新** [references/log-analysis.md](references/log-analysis.md)，补充新发现的日志术语或 grep 模式。

4. 更新时保持增量追加，不覆盖已有案例。

### 边界

- 不记录敏感信息（SIM 卡号、设备 IMEI、IP 地址等），用占位符替代
- 不记录未经验证的推测为"已知结论"
- 用户未明确同意时不写入案例库
- 如果案例与已有案例高度相似，追加备注而非新建条目

## 注意事项

- 日志时间戳格式：[级别)YYYYMMDDHHMMSS.mmm module:line
- 部分日志使用旧时间戳 202208011200xx（未校时），以文件名为准
- pstore/console-ramoops 记录的是最近一次重启前的 console 输出
- 解密工具 dfx_common_new.exe 路径不能含中文（GBK 编码问题），脚本已处理
