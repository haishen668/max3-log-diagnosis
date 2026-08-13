# Max3 日志诊断技能（max3-log-diagnosis）

用于华为/鼎桥 CPE-MAX3 系列（IC5980 等）加密诊断包的一键解密与设备日志分析。可作为 [Codex](https://codex.openai.com) 技能安装，让 AI 自动完成解密、日志读取、异常诊断，并从实际案例中持续学习。

## 功能

- **一键解密**：自动识别 IC5980 诊断包格式（.zip / .tar），调用 dfx_common_new.exe 解密，输出明文日志
- **日志分析**：解析应用层（app.log）、内核层（kmsg.log）、pstore 重启记录、基带日志中的异常
- **案例自积累**：每次诊断后经用户确认，自动将根因和解决方案写入案例库，下次遇到同类问题可直接匹配

## 安装

### 方式一：安装到 Codex 技能目录（推荐）

```powershell
# 克隆到 Codex 技能目录
git clone https://github.com/haishen668/max3-log-diagnosis.git "$env:USERPROFILE\.codex\skills\max3-log-diagnosis"
```

安装后，在 Codex 中把 IC5980 诊断包发给 AI，说"分析一下"或"看看为什么掉线"即可自动触发。

### 方式二：手动下载

1. 下载或克隆本仓库
2. 将整个文件夹复制到 `~/.codex/skills/max3-log-diagnosis`

## 使用方法

### 在 Codex 中使用（推荐）

安装技能后，直接向 AI 提供诊断包并描述问题：

> "设备 IC5980_xxxx.zip，MQTT 平台显示频繁离线，帮忙看一下"

AI 会自动：解密诊断包 → 查案例库匹配已知问题 → 分析日志 → 给出根因和建议 → 询问是否将本次案例入库

### 单独运行解密脚本

不依赖 Codex 也能解密：

```powershell
.scriptsDecrypt-IC5980.ps1 'C:DownloadsIC5980_xxxx.zip'
```

可选参数：

```powershell
.scriptsDecrypt-IC5980.ps1 'C:DownloadsIC5980_xxxx.zip' -OutDir 'D:logs'
```

解密后日志输出到 `DesktopIC5980-Decrypted<包名>mobilelog`，包含：

| 目录 | 内容 |
|---|---|
| `log/` | 应用日志（app.log-*.gz） |
| `kernel/` | 内核日志（kmsg.log-*.gz） |
| `pstore/` | 重启记录（console-ramoops） |
| `modem_log/` | 基带日志 |

## 目录结构

```
max3-log-diagnosis/
├── SKILL.md                      # 技能入口：触发条件、使用流程、自我更新机制
├── agents/
│   └── openai.yaml               # Codex UI 元数据
├── references/
│   ├── log-analysis.md           # 日志术语映射表 + grep 关键词模式
│   └── case-library.md           # 已验证案例库（持续积累）
└── scripts/
    ├── Decrypt-IC5980.ps1        # 一键解密脚本
    └── decrypt-tool/             # dfx 解密引擎
        ├── dfx_common_new.exe
        ├── 7za.exe
        ├── ATPLOG_DESC_EMUI_001.xml
        └── ATPLOG_ENUMDESC_EMUI_001.xml
```

## 已有案例

案例库（references/case-library.md）已收录：

- **CASE-001**：固件自愈重启（system self-healing）— 设备不定期自动重启
- **CASE-002**：MQTT 平台频繁离线 — 4G/5G 制式切换导致 TCP 长连接断开
- **CASE-003**：短时 LTE 无服务后自动恢复 — 覆盖/小区选择不稳定

每个案例包含：症状、根因、可 grep 的日志特征、解决方案、确认状态。

## 环境要求

- Windows + PowerShell（解密脚本依赖）
- 解密工具路径不能含中文（GBK 编码限制，脚本已自动处理）

## 许可

解密工具（dfx_common_new.exe、7za.exe）归属华为/鼎桥，本仓库仅用于封装调用流程。案例库和脚本可自由使用。
