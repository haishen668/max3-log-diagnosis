# AT 命令补采

仅在用户授权访问设备调试通道后使用。不同固件的命令支持范围可能不同；查询返回 `ERROR`不自动代表设备故障。

## 只读基线

```text
AT
ATI
AT+CFUN?
AT+CPIN?
AT+CEREG?
AT+COPS?
AT^SYSINFOEX
AT^HCSQ?
AT+CSQ
AT+CESQ
AT+CGATT?
AT+CGACT?
AT+CGDCONT?
AT+CGPADDR
```

## 小区和控制状态

```text
AT^MONSC
AT^MONSSC
AT^LCACELL?
AT^RRCSTAT?
AT+CSCON?
```

连续记录 RAT、Band、EARFCN/NR-ARFCN、PCI、ECI/NCI/Cell ID、TAC、RSRP、RSRQ、SINR 和 RRC 状态。正常时先建立基线，异常时每 3-5 秒采一轮，至少保留三轮并带终端时间戳。

## 判断

- Telnet/Linux 仍可用但 `AT`无响应：优先怀疑主控到模组控制通道、模组固件状态或供电。
- `CEREG=2/3/4`：分别表示搜索、拒绝或未知，应继续采运营商和拒绝原因。
- 已注册但 `CGATT=0`：分组域附着失败。
- 已注册、`CGATT=1`但 PDP 未激活：检查 APN、PDP 类型和运营商策略。
- 已注册、有 IP，但 MQTT 失败：检查路由、DNS、专网 ACL、TCP 和 MQTT Keep Alive。

## 有业务影响的命令

在异常证据采完前不要执行：

```text
AT+CFUN=0
AT+CFUN=1,1
AT+COPS=...
AT+CGDCONT=...
AT^SYSCFGEX=...
```

`AT+COPS=?`完整搜网可能持续数分钟并影响业务，不要周期执行。锁频、锁小区、修改 APN 或重置模组必须作为限时实验，先记录基线并准备回退配置。
