# SoundFinder for Alfred

<img src="icon.png" width="112" height="112" alt="SoundFinder 图标：放大镜内的声波">

**找出 Mac 上的声音来自哪个应用，或哪一张 Chrome 标签页。**

SoundFinder 是一个使用 Swift 编写的 Alfred 工作流。在 Alfred 输入 `sound`，
即可查看活跃的音频输出应用、进程和 Chrome 发声标签页，并跳转到声音来源。
无需 Chrome 扩展、远程调试或后台常驻服务。

## 功能

- **应用与进程定位**：通过 Core Audio 查询活跃输出流，显示应用名称、实际输出进程 PID 和输出设备。
- **Chrome 标签页定位**：读取原生辅助功能声音标记，区分发声页与已静音页，包括普通后台标签页。
- **直接跳转**：回车切到已有应用或原标签页，不重新打开网页；切换前重新核对目标。
- **实时筛选**：列表打开时每 2 秒刷新，支持按应用名、进程名、PID、设备和标签页标题筛选。
- **本地运行**：不录音、不采样音频、不联网、不读取浏览器历史，也不会自动暂停或关闭内容。

> “输出流活跃”不等于一定有可听见的声音。应用可能保持音频通道打开，
> 或持续输出静默数据。Chrome 的“已静音”标签也会明确标注，不视为正在发声。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 14.4 或更高版本 |
| Alfred | Alfred 5，已启用 Powerpack |
| Chrome 标签页检测 | Google Chrome 英文界面；需要 macOS 辅助功能权限 |
| 从源码构建 | Swift 5.9+、Xcode 或 Command Line Tools、Python 3 |

已在 macOS 26.7 / Apple Silicon 上构建和验证。构建脚本生成本机架构的二进制；
Intel Mac 的兼容性尚未实测。工作流安装包包含编译好的程序，
**运行工作流不需要 Swift、Python 或 Xcode**。

## 安装

当前仓库提供源码和打包脚本；安装包在本地构建后生成，不提交到 Git。

```sh
git clone https://github.com/lionoggo/soundfinder-alfred.git
cd soundfinder-alfred
bash scripts/build.sh
open dist/SoundFinder-1.1.2.alfredworkflow
```

在 Alfred 的导入窗口确认安装或更新“声音来源 · SoundFinder”。
打包脚本会先运行测试，再生成本地 ad-hoc 签名的安装包；不自动修改已安装工作流，
也不执行 Apple 公证或 GitHub 发布。

## 使用

唤起 Alfred，输入 `sound`；必要时在关键词后加一个空格。

| 操作 | 效果 |
| --- | --- |
| `sound` | 查看 Chrome 标记的发声/静音标签页，以及音频输出应用和进程 |
| `sound chrome` | 筛选 Chrome 相关结果 |
| `sound 耳机` | 按输出设备筛选应用和进程 |
| `sound 1234` | 按音频进程 PID 筛选 |
| `sound 视频标题` | 按 Chrome 标签页标题筛选 |
| 回车 | 收起 Alfred，再切换到原应用或原标签页 |
| `⌘C` | 复制来源详情 |
| `⌘L` | 放大显示来源信息 |

浏览器的音频 Helper 会归到主应用，复制详情时仍保留每个实际音频进程的 PID。
无法归属到可激活应用的后台进程只提供查看和复制，不尝试结束进程。

### Chrome 辅助功能授权

如果显示“授权 Chrome 标签页检测”，选择该项并回车，打开：

**系统设置 → 隐私与安全性 → 辅助功能**

按系统提示允许 Alfred 或 soundfinder，再重新运行 `sound`。
仅打开结果列表不会主动弹出权限申请。本地终端获准不代表 Alfred 启动的程序也已获准，
请以实际运行环境的提示为准。

没有这项权限时，应用和进程检测仍可使用。无需麦克风、屏幕录制、
AppleScript 自动化、“允许来自 Apple Events 的 JavaScript”或 Chrome 调试权限。

### 关闭 Chrome 检测

在 Alfred 工作流配置中取消勾选“启用 Chrome 发声标签页检测”，
即可只保留应用和进程检测，无需回退到旧版本。

命令行中也可以设置：

```sh
soundfinder_chrome_ax=0 .build/release/soundfinder alfred
```

## 工作原理

**应用层**查询 Core Audio 的进程对象和输出状态，并结合进程可执行路径查找所属应用。
查询失败或来源退出时保留警告，不把读取失败当成“没有声音”。

**Chrome 层**只遍历浏览器原生标签栏控件，跳过网页正文和工具栏。
识别辅助功能标签中的 `Audio playing` / `Audio muted`，不安装扩展、不执行网页脚本。
列表显示标签页标题，不保证取得网址。

**跳转层**重新扫描并核对进程、标签栏位置、标题和声音状态。目标变化、
重复发声标题或读取不完整时提示刷新，不猜测跳转目标。
应用激活后等待并检查实际前台进程，不把“请求已发送”当成切换成功。

## 隐私与已知限制

运行时不上传数据、不读取 Cookie 或浏览器历史、不录音、不采样音频，
不修改系统音量，也不创建后台服务。只有手动选择结果并回车时才尝试切换窗口；
检测本身不激活窗口、不展开标签组。

- 应用输出流可能包含静默数据，不能用来测量实际音量。
- Chrome 发声状态消失有短暂延迟；短促提示音可能错过两次检测之间的采样时机。
- 当前只适配并验证了英文 Chrome 标记；其他界面语言尚未适配，其他浏览器只有应用级定位。
- 折叠、隐藏、最小化窗口、多配置文件及特殊窗口未经过完整覆盖验证，结果可能不完整。
- 标题或标签栏结构变化后可能需要重新选择；同一 Chrome 进程中的同名发声标签可能拒绝跳转。
- 辅助功能文字识别不是安全边界。网页标题刻意仿造标记后缀可能导致误判，
  因此本工具不执行自动关闭、静音或其他破坏性操作。
- 不记录历史播放，没有窗口的系统服务或命令行播放器可能无法切到前台。

详细实测记录与未覆盖场景见 [Chrome 辅助功能验证记录](docs/chrome-ax-validation.md)。

## 开发与测试

```sh
# 编译、测试、签名、打包
bash scripts/build.sh

# 只运行 Swift 单元测试
swift test

# 应用/进程 JSON
.build/release/soundfinder list

# Chrome 发声/静音标签 JSON、权限状态和扫描警告
.build/release/soundfinder chrome-list

# Alfred Script Filter JSON
.build/release/soundfinder alfred chrome

# 检查实际安装包的连接、回车行为和参数传递
python3 scripts/test_workflow.py dist/SoundFinder-1.1.2.alfredworkflow

# 用全零 PCM 和音量为 0 的播放器验证真实音频输出启停
swift scripts/smoke_audio.swift ./dist/SoundFinder/soundfinder
```

测试覆盖音频进程归属、浏览器 Helper 合并、筛选、Chrome 标记解析、跳转参数、
权限兜底、异步应用激活、缺省图标，以及安装包连接配置和图标文件。

`scripts/probe_chrome_ax.swift` 是辅助功能开发诊断工具，会输出全部原生标签的元数据，
**不要公开分享其完整输出**。`Tests/fixtures/` 包含手动验证页，默认不播放；
非零信号按钮为 -60 dBFS，120 秒后自动停止。测试程序不修改其他播放器或系统音量。

### 项目结构

```text
Sources/
  SoundFinder/          命令行入口
  SoundFinderCore/      Core Audio、Chrome 辅助功能与 Alfred 输出
Tests/
  SoundFinderCoreTests/ Swift 单元测试
  fixtures/            手动验证页面
scripts/               构建、打包与集成验证脚本
assets/                可编辑 SVG 图标源图及导出说明
icon.png               Alfred 工作流图标和缺省结果图标
docs/                  实测记录
dist/                  本地生成的工作流安装包，不提交到 Git
```

## 版本与故障排查

当前版本为 **v1.1.2**，新增专属图标，并为后台进程、空结果、权限提示和错误提供图标。
应用和 Chrome 标签页结果继续显示原应用的图标。图标源图和导出说明见 [assets](assets/README.md)。

- **回车后仍停留在 Alfred**：确认安装 v1.1.1 或更高版本。
  该版本修复了连接误启用“Don't close Alfred”的问题，并补上实际前台进程检查。
- **只出现 Chrome 应用，没有具体标签页**：检查辅助功能授权、工作流配置中的 Chrome 开关，
  以及 Chrome 是否使用英文界面；应用活跃输出流也可能只是静默数据。
- **提示目标已变化或结果不完整**：重新运行 `sound`，不要强制复用过期结果。

v1.0 和 v1.1.0 含有回车不收起 Alfred 的连接配置问题，不建议为了关闭 Chrome 检测而降级。

## 卸载

在 Alfred Preferences → Workflows 中选中“声音来源 · SoundFinder”并移除。
不需要卸载后台服务或还原浏览器设置。若专门授予过辅助功能权限，可在系统设置中撤销。

## 维护者

[lionoggo](https://github.com/lionoggo)
