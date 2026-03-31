# CLAUDE.md

## 项目概览
- 这是一个 macOS Swift 命令行工具，用于监听默认音频输出设备。
- 当当前输出设备或输出源被识别为耳机时，如果系统音量超过 20%，程序会自动将音量压回 20%。
- 最低兼容系统为 macOS 13。

## 代码结构
- `Sources/VolumeGuardian/main.swift`：核心逻辑，负责监听默认输出设备变化、监听设备音量/输出源变化，并在耳机场景下执行音量限制。
- `scripts/install-launch-agent.sh`：构建 release 版本、生成 LaunchAgent plist、加载并启动登录自启服务。
- `scripts/uninstall-launch-agent.sh`：卸载 LaunchAgent。
- `README.md`：面向使用者的中文说明。

## 运行与验证
- 临时运行：`swift run volume-guardian`
- 安装为登录后自动运行：
  - `chmod +x scripts/install-launch-agent.sh scripts/uninstall-launch-agent.sh`
  - `./scripts/install-launch-agent.sh`
- LaunchAgent 日志目录：`~/.local/share/volume-guardian/logs/stdout.log`、`~/.local/share/volume-guardian/logs/stderr.log`
- 可执行文件安装路径：`~/.local/bin/volume-guardian`

## 行为约定
- 当前音量上限为 20%，在代码中以 `maximumVolumeScalar = 0.2` 表示。
- 耳机识别依赖设备名或输出源名关键字匹配，关键字位于 `headphoneKeywords`。
- 程序同时监听默认输出设备变化和具体设备属性变化；为应对某些设备的回写行为，使用短时重复限幅定时器补偿。

## 修改建议
- 修改音量上限时，同时保持用户文案与日志中的“20”一致。
- 修改耳机识别规则时，优先沿用现有“设备名/输出源名关键字匹配”的实现方式。
- 修改启动/安装流程时，注意与 README 中的使用说明保持同步。
- 除非确有必要，不要新增抽象层；当前项目规模较小，直接保持实现清晰即可。

## 开发注意事项
- 这是本地 macOS 工具，不涉及服务端或网络通信。
- 涉及 CoreAudio 属性监听时，注意先确认属性是否存在，再注册监听或读写属性。
- 如果改动 LaunchAgent 相关脚本，避免破坏日志路径、可执行文件路径和 `launchctl` 的加载流程。
