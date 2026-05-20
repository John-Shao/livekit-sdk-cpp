# RV1126B BoardLoopback 手动测试指南

> 适用版本：`port/rv1126b-on-upstream-v0.3.3`（tag `v0.3.3-rv1126b-phase8`）
> 最后更新：2026-05-20

板子 WiFi 不稳定时，推荐通过**串口控制台**直接操作。本文档覆盖：WSL SSH 环境配置、部署、启动、HTTP API 验证、常见问题。

> **所有宿主机命令均在 WSL 中执行**（`root@DESKTOP-72PRKBU`），除非特别说明。

---

## 1. 硬件与连接

| 项 | 值 |
|---|---|
| 板子型号 | ATK-DLRV1126B（aarch64, Linux 6.1, Buildroot 2024.02）|
| 屏幕 | 720×1280 竖屏 MIPI DSI |
| 摄像头 | `/dev/video-camera0`（1280×720 横向输出，物理竖装）|
| 音频 | ES8389 codec，ALSA card 0 |
| 板子 IP | `192.168.10.235`（固定，已配 SSH 别名 `rv1126b-board`）|
| 构建 VM IP | `192.168.126.129`（固定，SSH 别名 `rv1126b-vm`）|
| 串口 | USB-TTL 115200 8N1，板子端 `/dev/ttyS2` 或 `/dev/ttyFIQ0` |

---

## 2. WSL SSH 环境配置（首次 / 新 WSL 实例）

Windows 的 SSH key 在 `C:\Users\19146\.ssh\`，WSL 的 SSH 客户端使用自己的
`~/.ssh/`。需要将 key 注入 WSL（复制一份，不能用 symlink——`/mnt/c/` 挂载不支持 chmod 600）。

```bash
# 在 WSL 中执行
mkdir -p ~/.ssh

# 复制 SSH keys（Windows 路径 → WSL）
cp /mnt/c/Users/19146/.ssh/id_rv1126b_board ~/.ssh/id_rv1126b_board
cp /mnt/c/Users/19146/.ssh/id_rv1126b_vm    ~/.ssh/id_rv1126b_vm

# SSH 要求私钥权限必须是 600，否则拒绝使用
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rv1126b_board ~/.ssh/id_rv1126b_vm

# 写 WSL 的 SSH config（如果还没有）
cat > ~/.ssh/config << 'EOF'
Host rv1126b-vm
    HostName 192.168.126.129
    User alientek
    IdentityFile ~/.ssh/id_rv1126b_vm
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new

Host rv1126b-board
    HostName 192.168.10.235
    User root
    IdentityFile ~/.ssh/id_rv1126b_board
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config
```

验证：

```bash
ssh rv1126b-vm   'echo vm ok'
ssh rv1126b-board 'echo board ok'
```

> **每次 WSL 重建**（`wsl --shutdown` 后首次开新 distro）都需重复本节。
> WSL 实例数据持久化，通常只需配置一次。

---

## 3. 重装公钥（板子每次重启后）

板子 rootfs 是 overlay，`/root/.ssh/` 在重启后回到出厂状态，需重装公钥。
板子 root 密码：`rockchip`。

```bash
# 在 WSL 中执行，出现密码提示时输入 rockchip
ssh-copy-id -i ~/.ssh/id_rv1126b_board.pub root@192.168.10.235

# 或手动方式（ssh-copy-id 不可用时）
ssh root@192.168.10.235 \
  'mkdir -p /root/.ssh && \
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHoUYAf/Ws8wWErE03TX+4Ab1KYvQS0BfNKPqyek1IA claude-code@rv1126b-board 20260424" \
   >> /root/.ssh/authorized_keys && \
   chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && echo done'
```

装完后测试无密码登录：

```bash
ssh rv1126b-board 'uname -a'
```

---

## 4. 部署文件到板子

```bash
# 在 WSL 中执行（项目根目录）
cd /mnt/d/workspace/Meeting/livekit-sdk-cpp-0.3.3

# 创建目标目录
ssh rv1126b-board 'mkdir -p /opt/livekit'

# 从构建 VM 拷贝二进制和共享库
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

## 5. LiveKit Token

测试房间使用固定 JWT：`f1d641ae-e19d-4461-8a8b-2582d4036798`

写到板子（只需写一次，重启后不会丢失——`/opt/livekit/` 在持久层）：

```bash
# 在 WSL 中执行
echo 'f1d641ae-e19d-4461-8a8b-2582d4036798' | \
  ssh rv1126b-board 'cat > /opt/livekit/.token && chmod 600 /opt/livekit/.token'
```

smoke.sh 会自动读取 `/opt/livekit/.token`，无需每次传 `--token` 参数。

---

## 6. 启动 BoardLoopback

### 6.1 串口控制台启动（推荐，WiFi 不稳时）

连上串口（115200 8N1）后在板子 shell 里操作：

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

### 6.2 SSH 启动（WiFi 稳定时，在 WSL 中执行）

```bash
ssh rv1126b-board 'cd /opt/livekit && BOARD_API_TOKEN=test123 ./smoke.sh --bg'
ssh rv1126b-board 'tail -f /tmp/smoke.log'
```

### 6.3 停止进程

```sh
# 板子上（BusyBox 没有 pkill，用 kill + PID）
kill $(ps | grep BoardLoopback | grep -v grep | awk '{print $1}')
```

---

## 7. HTTP API 验证

BoardLoopback 运行后在 `0.0.0.0:8080` 提供三个端点。以下命令在 **WSL** 中执行。

### 7.1 查询状态（无需认证）

```bash
curl http://192.168.10.235:8080/v1/meeting/status
# 正常返回：{"state":"idle","participant_count":0,"active_speaker":"","room_name":""}
```

### 7.2 入会

```bash
curl -X POST http://192.168.10.235:8080/v1/meeting/join \
  -H "Authorization: Bearer test123" \
  -H "Content-Type: application/json" \
  -d '{"url":"wss://live.jusiai.com","token":"f1d641ae-e19d-4461-8a8b-2582d4036798"}'
# 返回 202 Accepted
```

入会后查状态：

```bash
curl http://192.168.10.235:8080/v1/meeting/status
# {"state":"in_meeting","room_name":"<ROOM>","participant_count":1,"active_speaker":""}
```

### 7.3 退会

```bash
curl -X POST http://192.168.10.235:8080/v1/meeting/leave \
  -H "Authorization: Bearer test123"
# 返回 200
```

### 7.4 认证失败验证

```bash
curl -X POST http://192.168.10.235:8080/v1/meeting/join \
  -H "Content-Type: application/json" \
  -d '{"url":"wss://live.jusiai.com","token":"f1d641ae-e19d-4461-8a8b-2582d4036798"}'
# 应返回 401 Unauthorized（无 Bearer 头）
```

---

## 8. 显示验证场景

| 场景 | 操作 | 预期结果 |
|---|---|---|
| 入会前预览 | 启动后不入会，看板子屏幕 | 本地摄像头全屏显示（竖向正立）|
| 入会后分屏 | POST /join，远端有人讲话 | 上半屏=远端人脸，下半屏=本地摄像头（均竖向正立）|
| 手机退会后 | 远端 peer 离开房间 | 屏幕恢复全屏本地摄像头预览 |
| 板子退会后 | POST /leave | 屏幕恢复全屏本地摄像头预览 |
| 横屏布局 | 启动时加 `BOARD_DISPLAY_LAYOUT=landscape` | 左半=远端，右半=本地 |

---

## 9. 音频验证

```bash
# 在 WSL 中检查 ALSA 增益
ssh rv1126b-board 'amixer -c 0 cget numid=39 && amixer -c 0 cget numid=48'
# numid=39 (ADCL PGA) 应为 9 (+27 dB)
# numid=48 (DACL) 应为 155 (-18 dB, AEC sweet spot)

# 重新初始化音频
ssh rv1126b-board 'cd /opt/livekit && ./board-audio-setup.sh'
```

AEC 验证：对端说话时板子扬声器播放，不应产生回声循环。标定参数：`DAC=155, AEC_DELAY=300ms`。

---

## 10. 常见问题

### 端口 8080 被占用

```
[http] listen on 0.0.0.0:8080 failed
```

```sh
# 板子上
ps | grep Board
kill -9 <PID>
```

### V4L2 设备忙

```
[loopback] v4l2 S_FMT failed: Device or resource busy
```

同上，有残留 BoardLoopback 进程，kill 后重启。

### 公钥每次重启后失效

overlay rootfs 设计如此。每次重启执行第 3 节命令重装。如需持久化，把公钥写入板子 overlay 持久层（需 Buildroot 支持）。

### SSH 超时

```bash
# 在 WSL 中检查连通性
ping 192.168.10.235
# 如果超时，IP 可能变了，从路由器 DHCP 表或串口 `ip addr` 查新 IP
# 然后更新 WSL 的 ~/.ssh/config 里的 HostName
```

---

## 11. 一键部署脚本（WSL，网络稳定时）

```bash
#!/bin/bash
# 在 WSL 中执行，从项目根目录运行
set -e
cd /mnt/d/workspace/Meeting/livekit-sdk-cpp-0.3.3

BOARD=rv1126b-board
VM=rv1126b-vm
VM_BUILD=~/livekit/livekit-sdk-cpp-0.3.3/build-rv1126b

ssh $BOARD 'mkdir -p /opt/livekit'
scp ${VM}:${VM_BUILD}/bin/BoardLoopback $BOARD:/opt/livekit/
scp ${VM}:${VM_BUILD}/lib/liblivekit.so \
    ${VM}:${VM_BUILD}/lib/liblivekit_ffi.so $BOARD:/opt/livekit/
scp scripts/smoke.sh scripts/board-audio-setup.sh $BOARD:/opt/livekit/
ssh $BOARD 'chmod +x /opt/livekit/smoke.sh /opt/livekit/board-audio-setup.sh'
echo "deploy ok — $(ssh $BOARD 'ls -sh /opt/livekit/BoardLoopback')"
```

---

## 12. 测试矩阵（完整验收）

以下矩阵对应 Phase 8.4.6 验收标准（HTTP API 命令在 WSL 中执行）：

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
