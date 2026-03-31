# VolumeGuardian

在 macOS 上监听默认音频输出设备。当输出设备或输出源是耳机时，如果音量超过 20，就立即把它压回 20。

## 这是什么

你可以把它理解成一个“盯着系统音量的小程序”：

- 当你用耳机听声音时，它会检查系统音量。
- 如果音量被调到 20 以上，它会自动压回 20。
- 如果当前不是耳机输出，它就不会去限制音量。

## 兼容性

本工具最低兼容 macOS 13 (Ventura)。

## 临时使用

如果你只是想现在用一下，不想安装到系统里，按下面做：

```bash
swift run volume-guardian
```

运行后，这个终端窗口不要关。只要窗口开着，它就会一直工作。

看到类似下面的输出，就说明程序已经启动成功：

```text
Monitoring output: 外置耳机 / 外置耳机
VolumeGuardian is running. Headphone volume limit: 20
```

这两行的意思是：

- 它已经识别到当前输出设备
- 它已经开始工作

如果你想停止它：

- 回到这个终端窗口
- 按 Control + C

## 怎么验证它真的生效了

1. 先插上耳机，或者连接 AirPods。
2. 运行上面的命令。
3. 手动把系统音量拉高到 20 以上。
4. 如果程序正常工作，音量会很快被压回 20。

## 开机后自动运行

如果你不想每次都手动打开终端，可以把它安装成登录后自动运行。

第一次安装时，运行：

```bash
chmod +x scripts/install-launch-agent.sh scripts/uninstall-launch-agent.sh
./scripts/install-launch-agent.sh
```

安装完成后，它会在你登录 macOS 时自动启动。

安装脚本会自动帮你做这些事：

- 构建 release 版本
- 将可执行文件安装到 `~/.local/bin/volume-guardian`（避免 macOS TCC 对 `~/Documents` 等目录的访问限制）
- 对可执行文件进行 ad-hoc 签名
- 生成并加载 LaunchAgent plist

安装完成后，可以这样确认它真的已经跑起来：

```bash
launchctl print "gui/$(id -u)/com.voice.volume-guardian"
```

再检查日志：

- `~/.local/share/volume-guardian/logs/stdout.log`
- `~/.local/share/volume-guardian/logs/stderr.log`

正常情况下，`stdout.log` 里应该能看到类似：

```text
VolumeGuardian starting. Waiting for audio events...
Monitoring output: 外置耳机 / 外置耳机
VolumeGuardian is running. Headphone volume limit: 20
Clamped volume to 20 for 外置耳机 / 外置耳机 [device change]
```

如果以后你不想用了，执行：

```bash
./scripts/uninstall-launch-agent.sh
```

## 日志

日志使用 macOS 统一日志系统，可以通过以下命令查看：

```bash
log stream --predicate 'subsystem == "com.voice.volume-guardian"' --level info
```

## 卸载后音量仍被限制？

如果执行了 `./scripts/uninstall-launch-agent.sh` 之后音量仍然被限制，说明除了 LaunchAgent 之外，还有其他方式启动的 `volume-guardian` 进程在运行（比如之前通过 `swift run` 在终端里手动启动的）。

排查步骤：

1. **检查是否还有进程在运行：**

```bash
pgrep -fl volume-guardian
```

如果没有输出，说明没有残留进程，问题在别处。如果有输出，你会看到类似：

```text
22214 /Users/alan/Documents/VolumeGuardian/.build/release/volume-guardian
```

2. **终止所有残留进程：**

```bash
pkill -f volume-guardian
```

3. **确认已全部清理：**

```bash
pgrep -fl volume-guardian
```

这次应该没有任何输出，音量限制也会立即解除。

## 补充说明

- 这是一个 macOS 小工具，只在你的电脑上运行。
- 项目是用 Swift 写的，但你日常使用时不用懂 Swift。
- 你真正需要记住的命令通常只有两个：

```bash
swift run volume-guardian
./scripts/install-launch-agent.sh
```
