# macOS 版任务管理器

对标 **Windows 11 任务管理器**的 macOS 系统监视器。一个窗口就能回答：什么在跑、谁在吃 CPU、
内存被谁占了、GPU 在忙什么 —— 卡死的程序也能直接结束掉。

免费、开源，**不要密码，也不申请任何系统权限**。

[English](README.md) · [简体中文](README.zh-CN.md)

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![Release](https://img.shields.io/github/v/release/ethan6945/macos-task-manager?include_prereleases)](https://github.com/ethan6945/macos-task-manager/releases/latest)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-ffdd00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/ethan6945)

![性能页](docs/screenshots/performance-cpu.png)

---

## 下载

去 [**Releases**](https://github.com/ethan6945/macos-task-manager/releases/latest) 下最新的 `.dmg`，
打开后把 **Task Manager** 拖进「应用程序」。

**运行要求：** macOS 14 或更新，Apple Silicon / Intel 都行。

### 第一次打开一定会被拦，这是正常的

这个 App 没有经过 Apple 公证（公证需要付费的开发者账号）。macOS 会拒绝第一次启动，甚至说它
「已损坏」。它没有损坏。**只需做一次**：

**系统设置 → 隐私与安全性 →** 拉到最底 **→ 仍要打开 →** 确认。

或者用终端一行搞定：

```bash
xattr -dr com.apple.quarantine "/Applications/Task Manager.app"
```

> macOS 15 Sequoia 之后，老办法「右键 → 打开」对未公证的 App 已经失效。

不想跑网上下的二进制？[自己编译](#从源码编译)，一分钟的事，也不需要 Xcode。

---

## 功能

### 性能

五个子页，每个都有 60 秒的实时曲线。

- **CPU** —— 总利用率，或切成每个逻辑处理器一格，**性能核和能效核分得清清楚楚**。还有进程数、
  线程数、打开文件数、开机时长、芯片型号、核心构成和各级缓存。
- **内存** —— 一条**内存构成条**，直接告诉你内存被谁吃了：App 内存、联动、已压缩、已缓存文件。
  另有内存压力曲线、交换区、换页统计，以及内存类型和制造商。
- **GPU** —— 利用率，**渲染器和分块器两个引擎**分开画，已分配和使用中的显存，GPU 核心数。
  活动监视器根本没有 GPU 页。
- **磁盘** —— 活动时间、读写速率、IOPS、平均响应时间，以及每个卷的容量。
- **网络** —— 每张网卡的收发曲线、累计流量、链路速度、IPv4 / IPv6 / MAC。

### 进程

所有进程一屏看全，分成**应用**和**后台进程**两组，带 CPU、内存、磁盘、线程、能耗、PID、用户。
点列头排序，按名字或 PID 搜索，工具栏和右键菜单都能**结束进程**或**强制结束**。

### 详细信息

同一份列表，但有 16 列，需要看真实数据时用：状态、架构、父进程、优先级、CPU 时间、端口、
页面调入、上下文切换、启动时间、完整路径。选中一个进程能看到它的命令行，右键还能**设置优先级**。

### 启动应用

开机或登录时由 launchd 拉起的所有项目，含加载状态、是否登录时启动、是否保持运行。
你自己 `~/Library/LaunchAgents` 下的条目可以启用/停用。

### 服务

当前用户会话里的 launchd 作业 —— 标识符、PID、上次退出码。运行中的服务可以直接跳到
详细信息页定位到它的进程。

### 用户

登录会话，按用户汇总 CPU、内存和进程数，展开可以看该用户的所有进程。

### 应用历史记录

按 App 累计的 CPU 时间、峰值内存和磁盘读写，从你第一次运行任务管理器开始记。


<details>
<summary><b>每个页面的截图</b></summary>

| | |
|---|---|
| **进程** | ![进程](docs/screenshots/processes.png) |
| **性能 › 内存** | ![内存](docs/screenshots/performance-memory.png) |
| **性能 › GPU** | ![GPU](docs/screenshots/performance-gpu.png) |
| **性能 › 磁盘** | ![磁盘](docs/screenshots/performance-disk.png) |
| **性能 › 网络** | ![网络](docs/screenshots/performance-network.png) |
| **详细信息** | ![详细信息](docs/screenshots/details.png) |
| **启动应用** | ![启动应用](docs/screenshots/startup.png) |
| **服务** | ![服务](docs/screenshots/services.png) |
| **用户** | ![用户](docs/screenshots/users.png) |
| **应用历史记录** | ![应用历史记录](docs/screenshots/app-history.png) |

</details>

---

## 怎么用

| | |
|---|---|
| **刷新速率** | 高 (1s) · 正常 (2s) · 低 (4s) · 暂停 —— 工具栏或「查看」菜单 |
| **外观** | 浅色、深色或跟随系统，另有 8 种强调色 |
| **语言** | 中文 / English，**切换即生效，不用重启** |
| **隐私模式** | 遮掉用户名和主机名、隐藏第三方启动项 —— 分享截图前打开它 |
| **保存窗口截图** | **⇧⌘S** 把窗口存成 PNG |
| **窗口置顶** | 「查看」菜单 |
| **设置** | **⌘,** |

---

## macOS 不允许做的几件事

这些在界面上都有标注，不做假数据：

- **按进程的网络流量、按进程的 GPU 占用** —— macOS 两个都没有公开接口。全局的 GPU 占用是有的，
  也显示了。
- **其他用户进程的磁盘 I/O 和命令行** —— 只能读到你自己的进程。
- **Apple Silicon 的 CPU 基准频率** —— 系统不暴露这个值。
- **结束其他用户或系统的进程** —— 本程序不申请管理员权限，所以这类操作会返回权限错误，
  并给出明确提示。

所有数据都走系统公开接口。没有后台服务、没有特权组件、不弹任何权限申请 —— 这也是它
从不问你要密码的原因。

---

## 从源码编译

不需要 Xcode，Command Line Tools + Swift 6 就够：

```bash
git clone https://github.com/ethan6945/macos-task-manager.git
cd macos-task-manager
make run
```

`make build` 生成 `build/Task Manager.app` · `make dmg` 打安装包 · `make stop` 关掉正在运行的实例。

---

## 请我喝杯咖啡

这是个免费的 MIT 开源小项目。如果它帮你省了点时间，可以
[**请我喝杯咖啡**](https://buymeacoffee.com/ethan6945) —— 纯自愿，这个 App 永远免费。

<a href="https://buymeacoffee.com/ethan6945"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-ffdd00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee" height="44"></a>

其实点个 star 一样有用 —— 那是别人能搜到它的原因。

## 参与

欢迎提 issue 和 PR。界面上的问题，用 **⇧⌘S** 存一张干净的截图附上就行。

## 许可

[MIT](LICENSE) · 致敬 [Dave Plummer](https://www.youtube.com/@DavesGarage) —— Windows NT 4.0 和
Windows 2000 的 `taskmgr.exe` 就是他写的。
