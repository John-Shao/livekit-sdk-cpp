# RV1126B BoardLoopback 手动测试指南

> 适用版本：`port/rv1126b-on-upstream-v0.3.3`（tag `v0.3.3-rv1126b-phase8`）
> 最后更新：2026-05-20

板子 WiFi 不稳定时，推荐通过**串口控制台**直接操作。本文档覆盖：部署、启动、HTTP API 验证、常见问题。

---

## 1. 硬件与连接

| 项 | 值 |
|---|---|
| 板子型号 | ATK-DLRV1126B（aarch64, Linux 6.1, Buildroot 2024.02）|
| 屏幕 | 720×1280 竖屏 MIPI DSI |
| 摄像头 | `/dev/video-camera0`（1280×720 横向输出，物理竖装）|
| 音频 | ES8389 codec，ALSA card 0 |
| SSH 别名 | `rv1126b-board`（`~/.ssh/config`，IP 靠 DHCP 可变）|
| 串口 | USB-TTL 115200 8N1，板子端 `/dev/ttyS2` 或 `/dev/ttyFIQ0` |

> **WiFi IP 经常变**（DHCP）。如果 `ssh rv1126b-board` 超时，先从串口或路由器查新 IP，更新 `~/.ssh/config` 里的 `HostName`，然后重新安装公钥（见第 2 节）。

---

## 2. 部署文件到板子

每次板子重启后 `/root/.ssh/authorized_keys` 会清空（overlay 文件系统）。部署前先装公钥：

```bash
# 在 Windows 终端里运行，密码是 rockchip
ssh root@<board-ip> 'mkdir -p /root/.ssh && \
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHoUYAf/Ws8wWErE03TX+4Ab1KYvQS0BfNKPqyek1IA claude-code@rv1126b-board 20260424" \
  >> /root/.ssh/authorized_keys && \
  chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && echo done'
```

公钥装好后，更新 `~/.ssh/config` 里的 HostName 为新 IP，然后部署应用文件：

```bash
# 创建目录
ssh rv1126b-board 'mkdir -p /opt/livekit'

# 从构建 VM 拷贝二进制和库
scp rv1126b-vm:~/livekit/livekit-sdk-cpp-0.3.3/build-rv1126b/bin/BoardLoopback \
    rv1126b-board:/opt/livekit/

scp rv1126b-vm:~/livekit/livekit-sdk-cpp-0.3.3/build-rv1126b/lib/liblivekit.so \
    rv1126b-vm:~/livekit/livekit-sdk-cpp-0.3.3/build-rv1126b/lib/liblivekit_ffi.so \
    rv1126b-board:/opt/livekit/

# 拷贝脚本
scp scripts/smoke.sh scripts/board-audio-setup.sh rv1126b-board:/opt/livekit/
ssh rv1126b-board 'chmod +x /opt/livekit/smoke.sh /opt/livekit/board-audio-setup.sh'
```

验证：

```bash
ssh rv1126b-board 'ls -la /opt/livekit/'
# 应看到：BoardLoopback  liblivekit.so  liblivekit_ffi.so  smoke.sh  board-audio-setup.sh
```

---

## 3. 生成 LiveKit Token

在开发机上生成入会 token（需安装 `lk` CLI）：

```bash
lk token create \
  --room <房间名> \
  --identity board-001 \
  --join \
  --valid-for 240h
```

或通过后端接口获取 JWT，写到板子：

```bash
echo '<JWT>' | ssh rv1126b-board 'cat > /opt/livekit/.token && chmod 600 /opt/livekit/.token'
```

---

## 4. 启动 BoardLoopback

### 4.1 串口控制台启动（推荐，WiFi 不稳时）

连上串口后直接在板子 shell 里操作：

```sh
cd /opt/livekit
export LD_LIBRARY_PATH=/opt/livekit:/usr/lib

# 后台运行，日志写 /tmp/smoke.log
BOARD_API_TOKEN=test123 ./smoke.sh --bg
tail -f /tmp/smoke.log
```

正常启动日志应包含：

```
[drm] connector 96 720x1280@60Hz
[drm] using plane 74 (NV12)
[loopback] DRM display ready — incoming video will render to MIPI panel
[http] listening on 0.0.0.0:8080
[daemon] waiting for HTTP /v1/meeting/join ...
```

### 4.2 SSH 启动（WiFi 稳定时）

```bash
ssh rv1126b-board 'cd /opt/livekit && BOARD_API_TOKEN=test123 ./smoke.sh --bg'
ssh rv1126b-board 'tail -f /tmp/smoke.log'
```

### 4.3 停止进程

```sh
# 板子上（BusyBox 没有 pkill，用 kill + PID）
kill $(ps | grep BoardLoopback | grep -v grep | awk '{print $1}')
# 或直接用 smoke.sh 的 leave API（见第 5 节）
```

---

## 5. HTTP API 验证

BoardLoopback 运行后在 `0.0.0.0:8080` 提供三个端点。从**同局域网的开发机**调用。

### 5.1 查询状态（无需认证）

```bash
curl http://<board-ip>:8080/v1/meeting/status
# 正常返回：{"state":"idle","participant_count":0,"active_speaker":"","room_name":""}
```

### 5.2 入会

```bash
curl -X POST http://<board-ip>:8080/v1/meeting/join \
  -H "Authorization: Bearer test123" \
  -H "Content-Type: application/json" \
  -d '{"url":"wss://live.jusiai.com","token":"<JWT>"}'
# 返回 202 Accepted
```

入会后查状态：

```bash
curl http://<board-ip>:8080/v1/meeting/status
# {"state":"in_meeting","room_name":"<ROOM>","participant_count":1,"active_speaker":""}
```

### 5.3 退会

```bash
curl -X POST http://<board-ip>:8080/v1/meeting/leave \
  -H "Authorization: Bearer test123"
# 返回 200
```

### 5.4 认证失败验证

```bash
curl -X POST http://<board-ip>:8080/v1/meeting/join \
  -H "Content-Type: application/json" \
  -d '{"url":"wss://...","token":"..."}'
# 应返回 401 Unauthorized
```

---

## 6. 显示验证场景

| 场景 | 操作 | 预期结果 |
|---|---|---|
| 入会前预览 | 启动后不入会，看板子屏幕 | 本地摄像头全屏显示（竖向正立）|
| 入会后分屏 | POST /join，远端有人讲话 | 上半屏=远端人脸，下半屏=本地摄像头（均竖向正立）|
| 手机退会后 | 远端 peer 离开房间 | 屏幕恢复全屏本地摄像头预览 |
| 板子退会后 | POST /leave | 屏幕恢复全屏本地摄像头预览 |
| 横屏布局 | 启动时加 `BOARD_DISPLAY_LAYOUT=landscape` | 左半=远端，右半=本地 |

---

## 7. 音频验证

```bash
# 检查 ALSA 增益设置
ssh rv1126b-board 'amixer -c 0 cget numid=39 && amixer -c 0 cget numid=48'
# numid=39 (ADCL PGA) 应为 9 (+27 dB)
# numid=48 (DACL) 应为 155 (-18 dB, AEC sweet spot)

# 重新初始化音频
ssh rv1126b-board 'cd /opt/livekit && ./board-audio-setup.sh'
```

AEC 验证：

- 对端说话时，板子本地扬声器播放远端语音，不应产生回声循环
- ERLE（回声抑制量）与 Phase 8.1 标定结果（`DAC=155, delay=300`）一致

---

## 8. 常见问题

### 端口 8080 被占用

```
[http] listen on 0.0.0.0:8080 failed
```

```sh
# 找到占用进程并杀掉
ps | grep Board
kill -9 <PID>
```

### V4L2 设备忙

```
[loopback] v4l2 S_FMT failed: Device or resource busy
```

同上，有残留 BoardLoopback 进程在跑，kill 后重启。

### 公钥每次重启后失效

板子 rootfs 是 overlay，`/root/.ssh/` 在重启后回到出厂状态。每次重启后需要重新安装公钥（见第 2 节）。如需持久化，把公钥写入 overlay 的持久层（视板子 Buildroot 配置决定是否支持）。

### stdbuf 命令不存在

smoke.sh 里已去掉 `stdbuf`，BusyBox 环境下可直接运行。如果看到旧版报错，重新 scp smoke.sh 到板子。

### SSH 超时 / IP 变了

```bash
# 1. 从路由器 DHCP 表或串口 ip addr 查新 IP
# 2. 更新 ~/.ssh/config 里的 HostName
# 3. 重装公钥（见第 2 节）
```

---

## 9. 完整部署一键脚本（网络稳定时）

```bash
#!/bin/bash
# 从开发机一键部署到板子
set -e
BOARD=rv1126b-board
VM=rv1126b-vm
LIVEKIT_BUILD=$HOME/livekit/livekit-sdk-cpp-0.3.3/build-rv1126b

ssh $BOARD 'mkdir -p /opt/livekit'
scp ${VM}:${LIVEKIT_BUILD}/bin/BoardLoopback $BOARD:/opt/livekit/
scp ${VM}:${LIVEKIT_BUILD}/lib/liblivekit.so \
    ${VM}:${LIVEKIT_BUILD}/lib/liblivekit_ffi.so $BOARD:/opt/livekit/
scp scripts/smoke.sh scripts/board-audio-setup.sh $BOARD:/opt/livekit/
ssh $BOARD 'chmod +x /opt/livekit/smoke.sh /opt/livekit/board-audio-setup.sh'
echo "deploy ok"
```

---

## 10. 测试矩阵（完整验收）

以下矩阵对应 Phase 8.4.6 验收标准：

| # | 场景 | 操作 | 通过标准 |
|---|---|---|---|
| T1 | 启动冒烟 | `./smoke.sh --bg` + 查日志 | DRM/V4L2/ALSA/HTTP 均初始化无 ERROR |
| T2 | 入会前预览 | 启动后不入会 | 屏幕显示本地摄像头实时画面（竖向正立）|
| T3 | HTTP 认证 | POST /join 不带 Bearer | 返回 401 |
| T4 | 入会 | POST /join 带 JWT | 返回 202，日志见 `[meeting] connected` |
| T5 | 分屏显示 | 入会后远端说话 | 上半=远端，下半=本地，均竖向正立 |
| T6 | active speaker 切换 | 多人轮流说话 | 屏幕跟随说话人 |
| T7 | 手机退会 | 远端 peer 离开 | 屏幕恢复全屏本地预览 |
| T8 | 板子退会 | POST /leave | 返回 200，屏幕恢复全屏本地预览 |
| T9 | 重复入会 | 在会中再 POST /join | 返回 409 |
| T10 | 音频双向 | 双方对话 | 无明显回声，AEC 收敛 |
