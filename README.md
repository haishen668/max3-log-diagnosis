# Max3 日志诊断（max3-log-diagnosis）

用于华为/鼎桥 CPE-MAX3 系列（IC5980 等）加密诊断包的解密与设备日志分析。

不绑定特定 AI 工具。任何能执行命令、能读文件的 AI agent 都能用：Codex、Claude、ChatGPT、Cursor、Copilot 等。

## 这个仓库能做什么

- 解密 IC5980 加密诊断包（diagnose_enc.tar）
- 自动分析设备日志中的网络异常、重启原因、MQTT 掉线、信号问题
- 案例库持续积累，遇到同类问题直接给出验证过的解决方案

## 安装（适用于所有 AI agent）

### 第一步：下载

```powershell
git clone https://github.com/haishen668/max3-log-diagnosis.git
```

或者直接下载 ZIP 解压。记住解压后的文件夹路径，下面会用到。

### 第二步：让你的 AI 知道这个工具的存在

根据你用的 AI 工具，选一种：

**Codex / OpenAI Codex**

把文件夹放到技能目录，AI 会自动发现：

```powershell
# Windows
move max3-log-diagnosis "%USERPROFILE%\.codex\skills\"

# macOS / Linux
mv max3-log-diagnosis ~/.codex/skills/
```

**Claude Code**

在你要分析日志的目录下创建或编辑 CLAUDE.md，加一行：

```
参考 /path/to/max3-log-diagnosis 文件夹中的 SKILL.md 和 references/ 来分析 IC5980 设备日志。
```

**Cursor / 其他支持规则文件的编辑器**

把 SKILL.md 的内容复制到你的规则配置（.cursorrules、.windsurfrules 等）中，或指向该文件。

**ChatGPT / 通用对话型 AI**

直接在对话里说（自然语言，不需要任何配置文件）：

> 我有一个 IC5980 设备的诊断包需要分析。我已经下载了这个工具：<你的路径>/max3-log-diagnosis。请先读 SKILL.md 了解流程，然后用 scripts 里的脚本帮我解密，再按 references 里的方法分析日志。诊断包路径是 <你的文件路径>。

**任何其他 AI agent**

核心就一句话，用你自己的话说：

> 读一下 /path/to/max3-log-diagnosis/SKILL.md，然后帮我解密和分析这个 IC5980 诊断包：<文件路径>

AI 读到 SKILL.md 就知道完整流程了。SKILL.md 是给 AI 看的说明书，不是给人看的。

## 使用

### 让 AI 帮你分析（推荐）

装好之后，把诊断包发给你的 AI，用自然语言描述问题就行：

- 设备频繁掉线，帮我看下这个诊断包
- MQTT 平台显示设备离线了，日志里能找到原因吗
- 这台 IC5980 不定时重启，查一下为什么

AI 会自动解密、查案例库、分析日志、给出结论。如果结论有价值，AI 会问你是否把这次案例存入案例库。

### 手动解密（不用 AI 也能用）

```powershell
.\scripts\Decrypt-IC5980.ps1 C:\Downloads\IC5980_xxxx.zip
```

解密后日志在 Desktop\IC5980-Decrypted\<包名>\mobilelog，包含：

| 目录 | 内容 |
|---|---|
| log/ | 应用日志（app.log-*.gz） |
| kernel/ | 内核日志（kmsg.log-*.gz） |
| pstore/ | 重启记录（console-ramoops） |
| modem_log/ | 基带日志 |

### 手动分析（给技术人员）

解密后的日志是 gzip 压缩的文本。解压后按 references/log-analysis.md 里的关键词表 grep 即可。三个常用入口：

- 看重启原因：搜索所有 kmsg.log 中的 [reb]
- 看网络异常：搜索 no service、DIALUP_STATE、sysmode
- 看 MQTT：搜索 wj_mqtt

## 文件说明

| 文件 | 谁看 | 作用 |
|---|---|---|
| SKILL.md | AI 读 | 完整的解密和分析流程指令 |
| README.md | 人看 | 你正在读的这个 |
| references/log-analysis.md | AI 读 | 日志术语翻译 + grep 关键词表 |
| references/case-library.md | AI 读 | 已验证案例库（持续积累） |
| scripts/Decrypt-IC5980.ps1 | AI 或人执行 | 一键解密脚本 |
| scripts/decrypt-tool/ | 解密脚本调用 | dfx 解密引擎 |

## 已收录的案例

案例库已包含三个经过用户确认的真实诊断：

1. 固件自愈重启 — 设备不定时自动重启，日志显示 system self-healing
2. MQTT 频繁离线 — 4G/5G 制式切换断开 TCP 长连接
3. 短时无服务 — LTE 覆盖波动导致秒级断网后自动恢复

每个案例都有可搜索的日志特征和验证过的解决方案。

## 案例库怎么更新

AI 每次完成诊断后，如果结论有价值，会问你“是否把这次案例加入案例库”。你同意后，AI 会按固定格式追加到 references/case-library.md。然后你 push 到 GitHub，所有设备就同步了：

```powershell
cd max3-log-diagnosis
git add references/case-library.md
git commit -m "add case: <案例标题>"
git push
```

## 环境要求

- Windows + PowerShell（解密脚本依赖）
- 路径不能含中文（工具编码限制，脚本已自动处理）
- git（用于克隆和同步案例库）

## 许可

解密工具（dfx_common_new.exe、7za.exe）归华为/鼎桥，本仓库仅封装调用流程。脚本和案例库内容可自由使用。