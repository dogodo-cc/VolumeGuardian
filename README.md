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
- 生成 LaunchAgent plist
- 自动加载 LaunchAgent

如果以后你不想用了，执行：

```bash
./scripts/uninstall-launch-agent.sh
```

## 日志

如果你安装成自动运行模式，日志会写到：

- `.logs/stdout.log`
- `.logs/stderr.log`

## 补充说明

- 这是一个 macOS 小工具，只在你的电脑上运行。
- 项目是用 Swift 写的，但你日常使用时不用懂 Swift。
- 你真正需要记住的命令通常只有两个：

```bash
swift run volume-guardian
./scripts/install-launch-agent.sh
```
