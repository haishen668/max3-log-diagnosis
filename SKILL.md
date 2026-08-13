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

## 案例库（一案例一文件）

案例存放在 references/cases/ 目录，每个案例一个 .md 文件，文件名格式 CASE-NNN-描述.md。索引见 [references/case-library.md](references/case-library.md)。

分析前，遍历 references/cases/ 目录，匹配是否与当前问题相似。匹配时引用案例中的日志特征帮助快速定位，但必须如实告知用户该案例的"验证状态"：

- **未验证**：只有日志诊断结论，建议方案尚未经用户确认。措辞用"建议尝试"，不说"一定能解决"。
- **用户确认有效**：方案已在该设备上验证有效（需要用户明确反馈"这个方法管用"后才能更新到此状态）。
- **用户确认无效**：方案已尝试但未解决问题（同样需要用户明确反馈）。

当前所有案例均为"未验证"状态。不要默认任何建议已确认。

## 自我更新机制

### 何时触发

满足以下任一条件：
- 诊断出了明确的根因
- 发现了新的日志模式或异常类型
- 用户主动确认某个建议方案是否有效（无论有效还是无效）
- 遇到了 cases/ 中未记录的新场景

### 新增案例

1. **诊断完成后**，向用户提问：
   - "这次分析结论对你有帮助吗？"
   - "你是否愿意把这个案例加入案例库？"

2. **仅在获得用户明确同意后**，在 references/cases/ 新建文件 CASE-NNN-描述.md，格式：

```markdown
# CASE-NNN: <标题>

- 设备型号 / 固件版本
- 症状：<现象>
- 根因：<日志证据支撑的结论>
- 关键日志特征：<可 grep 的关键词和时间模式>
- 建议：<建议步骤>
- 验证状态：未验证
- 日期：<YYYY-MM-DD>
```

3. 更新 references/case-library.md 索引，追加一行链接。
4. 补充新发现的日志术语到 [references/log-analysis.md](references/log-analysis.md)。

### 更新验证状态（重要）

当用户后续反馈某个建议是否有效时，编辑对应 CASE-NNN 文件，把"验证状态"改为：

- **用户确认有效**：在该建议下方补充"实际效果：<具体情况>"。
- **用户确认无效**：同样补充，并在建议中标明无效的方案，避免后续误导。

这是案例库从"假设"变成"知识"的关键路径，务必如实记录。

### 为什么一案例一文件

避免多人/多设备通过 git 同步案例库时产生合并冲突。新增案例 = 新增文件，git pull 永远不会冲突。只有 case-library.md 索引文件和 log-analysis.md 术语表可能需要合并，但它们是追加性质的，冲突概率低。

### 边界

- 不记录敏感信息（SIM 卡号、IMEI、IP 地址），用占位符替代
- 不把未经验证的推测记为"已确认"
- 用户未明确同意时不写入案例库
- 不修改其他已有的 CASE 文件，只新建或更新验证状态

## 注意事项

- 日志时间戳格式：[级别)YYYYMMDDHHMMSS.mmm module:line
- 部分日志使用旧时间戳 202208011200xx（未校时），以文件名为准
- pstore/console-ramoops 记录的是最近一次重启前的 console 输出
- 解密工具 dfx_common_new.exe 路径不能含中文（GBK 编码问题），脚本已处理
