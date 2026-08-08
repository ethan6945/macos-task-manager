# Task Manager for macOS

A **Windows 11 Task Manager**–style system monitor for macOS, built with SwiftUI and AppKit.
Seven pages, five performance sub-pages, full **CPU / memory / GPU / disk / network** monitoring —
with **no privileged helper, no `sudo`, and no permission prompts**.

A tribute to [Dave Plummer](https://www.youtube.com/@DavesGarage), who wrote the original
`taskmgr.exe` for Windows NT 4.0 / Windows 2000.

[English](README.md) · [简体中文](README.zh-CN.md)

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![Release](https://img.shields.io/github/v/release/ethan6945/macos-task-manager?include_prereleases)](https://github.com/ethan6945/macos-task-manager/releases/latest)

![Processes](docs/screenshots/processes.png)

---

## Why this exists

Activity Monitor is fine, but it is not a Task Manager. If you came from Windows you want
**one window** that answers: what is running, what is eating the CPU, how is memory actually
composed, what is the GPU doing, which services and login items are loaded, and how do I
kill the thing that is hanging.

That is what this is. Every page maps onto a Windows 11 Task Manager page.

## Features

| Page | What you get |
|---|---|
| **Processes** | Apps / background processes grouped, sortable and searchable: name · CPU · memory · disk · threads · energy · PID · user. End task (SIGTERM) and Force quit (SIGKILL). |
| **Performance › CPU** | Overall utilization graph plus a per-logical-processor grid that distinguishes **performance cores from efficiency cores**. Process, thread and open-file counts, uptime, cache sizes. |
| **Performance › Memory** | Usage graph, a **memory composition bar** (App / Wired / Compressed / Cached files), memory-pressure graph, swap, page-in/out counters, DIMM type and vendor. |
| **Performance › GPU** | Utilization graph plus **Renderer and Tiler** shown as two "GPU engines", VRAM allocated/in-use, GPU core count, unified memory. |
| **Performance › Disk** | Active time, read/write throughput, IOPS, average response time, per-volume capacity. |
| **Performance › Network** | Per-interface bi-directional throughput, totals, link speed, IPv4 / IPv6 / MAC. |
| **App history** | Per-app cumulative CPU time, peak memory and disk I/O, tracked and persisted by the app itself. |
| **Startup apps** | LaunchAgents / LaunchDaemons with load state, "run at load" and "keep alive". |
| **Users** | Login sessions from `utmpx` plus per-user resource totals, expandable to that user's processes. |
| **Details** | A 16-column process table with command line, architecture, ppid, nice, page-ins, context switches — and **Set priority**. |
| **Services** | launchd jobs in your user domain (label / PID / last exit status), with "go to details". |

Plus: a persistent status bar (processes / threads / CPU / memory / GPU), four update speeds
(High 1s · Normal 2s · Low 4s · Paused), **light / dark / system theme**, 8 accent colours, and
**English / 简体中文 that switch instantly without a restart**.

<details>
<summary><b>More screenshots</b></summary>

### Performance › CPU
![CPU](docs/screenshots/performance-cpu.png)

### Performance › Memory
![Memory](docs/screenshots/performance-memory.png)

### Performance › GPU
![GPU](docs/screenshots/performance-gpu.png)

### Performance › Disk
![Disk](docs/screenshots/performance-disk.png)

### Performance › Network
![Network](docs/screenshots/performance-network.png)

### Details
![Details](docs/screenshots/details.png)

### Services
![Services](docs/screenshots/services.png)

### Startup apps
![Startup](docs/screenshots/startup.png)

### Users
![Users](docs/screenshots/users.png)

</details>

---

## Download

Grab the latest `.dmg` from the [**Releases**](https://github.com/ethan6945/macos-task-manager/releases/latest) page,
open it, and drag **Task Manager** into your Applications folder.

### ⚠️ First launch will be blocked — this is expected

This app is **not notarized by Apple**, because notarization requires a paid Apple Developer ID.
macOS will refuse the first launch and may claim the app "is damaged". It is not. Do one of these,
once:

**Option A — System Settings**

1. Try to open the app (it gets refused).
2. Open **System Settings → Privacy & Security**.
3. Scroll to the bottom and click **Open Anyway** next to *Task Manager*, then confirm.

**Option B — Terminal (one line)**

```bash
xattr -dr com.apple.quarantine "/Applications/Task Manager.app"
```

> On macOS 15 Sequoia and later, the old "Control-click → Open" shortcut no longer works for
> un-notarized apps — you have to use one of the two options above.

If you would rather not trust a binary from the internet, [build it from source](#build-from-source);
it takes about a minute and needs no Xcode.

### Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel
- **No** admin password, **no** Full Disk Access, **no** Screen Recording, **no** helper tool

---

## Privacy mode

**View → Privacy mode** (also in Settings) masks the things that identify *you* before you
share a screenshot or a screen recording:

- login user names (uid ≥ 500) show as `user`
- the host name shows as `mac`
- the Services and Startup pages list only `com.apple.*` system jobs, so your third-party
  launch agents stay private

Process names are deliberately **not** masked — that is the app's actual content. Quit anything
you would rather not show before taking the shot.

The screenshots in this README were taken with privacy mode on.

## Build from source

Xcode is not required — Command Line Tools and Swift 6 are enough:

```bash
git clone https://github.com/ethan6945/macos-task-manager.git
cd macos-task-manager
make run
```

| Target | What it does |
|---|---|
| `make build` | Release build, assembles `build/Task Manager.app` |
| `make run` | Build and launch |
| `make debug` | Debug build (faster to compile) |
| `make dmg` | Build a distributable `.dmg` |
| `make icon` | Regenerate the app icon (`ICON_STYLE=chip\|pulse\|bars\|gauge`) |
| `make stop` | Quit a running instance |

---

## How it works

### Reading every process without elevation

An unsigned, unprivileged macOS app can only call `proc_pidinfo(PROC_PIDTASKALLINFO)` on
processes **owned by the same user**. Measured on a normal desktop: **291 of 691 processes
(42%) returned nothing** — no CPU, no memory. The `e_vm` and `p_pctcpu` fields in `kinfo_proc`
are all zero on modern macOS, so `sysctl` does not help either.

`/bin/ps` and `/usr/bin/top` see everything because they are **setuid root** *and* carry the
`com.apple.system-task-ports.read` entitlement — a restricted entitlement that Apple has to
grant you.

So this app keeps a resident `top -l 0` subprocess and parses its stream. Result:
**complete metrics for 100% of processes**, with zero elevation and zero permission dialogs.
The subprocess restarts itself if killed and is reaped when the app quits.

Everything else comes from public APIs:

| Data | Source |
|---|---|
| CPU, overall and per-core | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas |
| Memory | `host_statistics64(HOST_VM_INFO64)`, `hw.memsize`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` |
| GPU | `PerformanceStatistics` on the IORegistry `IOAccelerator` node; device specs from Metal |
| Disk | `Statistics` on `IOBlockStorageDriver`; volumes via `getmntinfo` |
| Network | `getifaddrs` `AF_LINK` (`if_data`) deltas; display names from SystemConfiguration |
| Process identity | `sysctl(KERN_PROC_ALL)`; paths from `proc_pidpath` |
| Per-process disk I/O | `proc_pid_rusage` |
| Services / startup / users | `launchctl list`, LaunchAgents & LaunchDaemons plists, `utmpx` |

### Performance

The process table is an **`NSTableView`** wrapped in `NSViewRepresentable`, not SwiftUI's `Table`.
Measured with ~690 processes at a 2-second refresh:

| Implementation | CPU |
|---|---|
| SwiftUI `Table` | 18–20% (a fixed cost of swapping the data, independent of row count) |
| `NSTableView`, cells using Auto Layout | 34% |
| `NSTableView`, manual cell layout + visible-rows-only reload | **12%** |

Three things mattered:

- **No Auto Layout in cells.** A few hundred constraints made `-[NSWindow layoutIfNeeded]` eat a
  third of the main thread.
- **`noteNumberOfRowsChanged` + reloading only visible rows** instead of `reloadData`, which purges
  every row view. (But a full `reloadData` *is* required when group-header row indices move — a row
  view's "is this a group row" is fixed at creation, so reloading only cells leaves blank rows.)
- **No `KeyPathComparator`.** Sorting 690 rows by name through its existential took 20 ms.

The Performance page costs about 7%. Selecting "Low" (4s) roughly halves everything.
For reference, Activity Monitor uses about 2% at its default 5-second refresh.

### Window snapshots

**⇧⌘S** saves the current window as a PNG using `CALayer.render(in:)` — the app draws its own
views in its own process, so **no Screen Recording permission is needed**. Setting
`TM_CAPTURE_DIR` makes it walk every page, save a PNG for each, and quit; that is how the
screenshots above are produced.

---

## What macOS will not let this app do

These are labelled in the UI rather than faked:

- **Per-process network traffic** — no public API. The bundled `nettop` uses the private
  NetworkStatistics framework and needs root.
- **Per-process GPU usage** — no public API either; only system-wide GPU utilization is available.
- **Disk I/O and command line for other users' processes** — `proc_pid_rusage` and
  `KERN_PROCARGS2` are same-user only.
- **CPU base frequency on Apple Silicon** — `hw.cpufrequency` is not exposed.
- **System-domain launchd jobs** — enumerating `system/` requires root, so only your user domain
  (`gui/<uid>`) is listed.
- **Killing other users' or system processes** — returns `EPERM` with a clear message. This app
  deliberately does not install a privileged helper or use the deprecated
  `AuthorizationExecuteWithPrivileges`.
- **App history** — macOS keeps no long-term per-app resource ledger, so the app accumulates its
  own from first run, stored in `~/Library/Application Support/TaskManager/app-history.json`.

---

## Project layout

```
Sources/TaskManager/
  TaskManagerApp.swift          @main, menus, Settings scene
  Model/
    SystemMonitor.swift         @MainActor @Observable — latest snapshot + history buffers
    SamplingEngine.swift         actor that owns every sampler
    AppHistoryStore.swift        per-app accounting and persistence
    Localization.swift           English/Chinese strings, switchable at runtime
    Theme.swift                  light/dark and accent colour
  System/                        one sampler per file, pure C APIs
    CPUSampler / MemorySampler / GPUSampler / DiskSampler / NetworkSampler
    ProcessSampler / TopStream / ServiceSampler / StartupSampler / UserSampler
  Views/
    RootView.swift               NavigationSplitView, seven pages, status bar
    Performance/{CPU,Memory,GPU,Disk,Network}View.swift
    Components/{ProcessTable,Graph,MetricGrid,IconCache,WindowSnapshot}.swift
Scripts/
  bundle.sh                      builds the .app without Xcode
  make-dmg.sh                    builds the distributable .dmg
  MakeIcon.swift                 draws the app icon with CoreGraphics
```

Sampling runs on the `SamplingEngine` actor and hands back `Sendable` value snapshots.
The whole project compiles **warning-free under Swift 6 strict concurrency**.

---

## Contributing

Issues and pull requests are welcome. If you are reporting a rendering problem, **⇧⌘S**
gives you a clean screenshot to attach.

## License

[MIT](LICENSE)
