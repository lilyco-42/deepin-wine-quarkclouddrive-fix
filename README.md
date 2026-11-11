# deepin-wine-quarkclouddrive-fix

> 让 AUR 的 **夸克网盘**（`deepin-wine-quarkclouddrive`）在 Arch / CachyOS / 非 Deepin 桌面上真正能启动。
> Making the AUR **Quark Cloud Drive** package actually work on Arch / CachyOS / any non-Deepin desktop.

![screenshot](docs/login.png)

<p align="center">
  <a href="../../releases/latest"><img alt="release" src="https://img.shields.io/badge/release-v3.2.6spark4--4-blue"></a>
  <img alt="platform" src="https://img.shields.io/badge/platform-Arch%20%7C%20CachyOS-1793d1">
  <img alt="de" src="https://img.shields.io/badge/desktop-KDE%20Wayland-1d99f3">
  <img alt="license" src="https://img.shields.io/badge/license-LicenseRef--custom-lightgrey">
</p>

---

## 这是什么

上游 AUR 包 [`deepin-wine-quarkclouddrive`](https://aur.archlinux.org/packages/deepin-wine-quarkclouddrive)
在 Deepin / UOS 之外的发行版上装完打不开 —— 有 **4 个互相独立的 bug** 叠在一起。
本仓库是修好的 `PKGBUILD` 与补丁文件，**预编译好的包放在 [Releases](../../releases/latest)**。

本机环境（已验证）：CachyOS（Arch 系）、内核 6.18、KDE Plasma 6、Wayland、2880×1800 @ 2x。

## 快速开始

```bash
# 从 Release 下载四个包后，一次装完（顺序无关，pacman 会处理）
sudo pacman -U \
  spark-transhell-1.1-5-x86_64.pkg.tar.zst \
  deepin-wine8-stable-8.16deepin25_1-1-x86_64.pkg.tar.zst \
  spark-dwine-helper-5.8_5.3.14-1-any.pkg.tar.zst \
  deepin-wine-quarkclouddrive-3.2.6spark4-4-x86_64.pkg.tar.zst
```

然后从应用菜单点「夸克网盘」，或终端执行 `deepin-wine-quarkclouddrive`。
首次启动会自动创建 Wine bottle（约 1 分钟），**不会弹任何对话框**。

自己构建：见下方 [从源码构建](#从源码构建)。

## 四个 bug

### 1. `--no-sandbox` 被夸克自研参数解析器拒绝（致命）

上游 `PKGBUILD` 里这句 sed 硬把参数塞进 desktop 文件的 Exec：

```bash
sed "s|\"/opt/apps/${pkgname}/files/run.sh\"|${pkgname} --no-sandbox|g"
```

但 `QuarkCloudDrive.exe` 不用标准 Electron 参数解析（exe 里能直接 grep 到 `bad option` 字符串）：

```
QuarkCloudDrive.exe: bad option: --no-sandbox    →  RC=9，立刻退出
```

`--no-sandbox=1`、`--enable-logging` 同样被拒（`--version` 是例外，返回 v16.13.2）。
Electron 的渲染进程本来就会自己带 `--no-sandbox`，根本不需要外部传。

**修复**：删掉这句 sed。

### 2. `ELECTRON_RUN_AS_NODE` 导致"启动两秒后静默退出"（最阴）

夸克网盘本身是 Electron 应用。若父进程注入了 `ELECTRON_RUN_AS_NODE=1`，它会以"纯 Node 解释器"
模式运行 —— 主进程脚本跑完就 `exit(0)`，**不建窗口、不打日志、无崩溃码**。

从 VS Code / Cursor / 任何 Electron IDE 的集成终端启动必然踩到。这种"退出"不是崩溃，
所以 `strace`、`+seh`、core dump 都查不出任何东西 —— 浪费最多时间的就是这个。

**修复**：启动脚本里 `unset ELECTRON_RUN_AS_NODE ELECTRON_NO_ATTACH_CONSOLE`，
在三个入口（`/usr/bin` 包装脚本、deb 的 `run.sh`、spark 钩子）都做。

### 3. zenity 缩放对话框卡死首次启动

`spark_run_v4.sh` → `set-wine-scale.sh` → 找不到 `$WINEPREFIX/scale.txt` 时调 `get-scale.sh`，
后者弹 `zenity --list`（700×350，手选 1.0~4.0 缩放）：

![zenity bug](docs/zenity-bug.png)

从自启动、脚本、桌面点击、无人值守场景启动时会**永久卡在这个弹窗**上 ——
看起来就是"装好了但打不开"。

**修复**：首次启动时按系统 `Xft.dpi` 自动推导缩放档位写进 `~/.config/spark-wine/scale.txt`，完全不弹窗。
本机 `Xft.dpi=192`、2880×1800 → 自动算出 **2.0**（对应 Windows 192 dpi）。

### 4. `cd: C:/windows/command: 没有那个文件或目录`

`spark_run_v4.sh` 的 CallProcess 只替换小写盘符：

```bash
path=$(echo ${path/c:/${WINEPREFIX}/drive_c})   # 只有小写 c:
```

而 lnk 分支传入的是大写 `C:/windows/command/start.exe` → 替换失败 → `cd` 到不存在的路径
→ 退回 `$HOME` 启动（污染工作目录）。这就是 AUR 评论区里反复出现的 `line 247: cd: ...`。

**修复**：传小写 `c:`，并在 spark 钩子里再兜一层大小写归一。

## 补丁打在哪些文件

| 文件 | 改动 |
|---|---|
| `src/PKGBUILD` | 删掉注入 `--no-sandbox` 的 sed；desktop 的 `Exec` 改指 `deepin-wine-quarkclouddrive`；顺手修 `run.sh` 的小写盘符 + unset `ELECTRON_*`；打包 spark 钩子 |
| `src/deepin-wine-quarkclouddrive.sh` → `/usr/bin/deepin-wine-quarkclouddrive` | `exec` 前 unset `ELECTRON_RUN_AS_NODE` / `ELECTRON_NO_ATTACH_CONSOLE`；`C:/windows/...` 改 `c:/windows/...` |
| `src/Deepin-QuarkCloudDrive.sh` → `/opt/deepinwine/tools/spark_run_v4_app_configs/Deepin-QuarkCloudDrive.sh` | spark 官方扩展钩子：① unset `ELECTRON_*`；② 自动推导缩放写 `scale.txt`；③ 盘符大小写归一 |
| `/usr/share/applications/deepin-wine-quarkclouddrive.desktop` | `Exec=deepin-wine-quarkclouddrive -u %u`，不再走 deb 里 `BOTTLENAME=Spark-QuarkCloudDrive` 的 `run.sh` |

> **为什么补丁放在 spark 钩子而不是 helper 自身**
> `spark_run_v4.sh` 的 `CallApp` 会优先 `source`
> `/opt/deepinwine/tools/spark_run_v4_app_configs/${BOTTLENAME}.sh`，没有才走通用启动。
> 这是 helper 自己设计的扩展点，所以补丁**不会被 `spark-dwine-helper` 升级冲掉**。

## 顺带排掉的假修复

AUR 评论区有些"修复"是给旧版准备的，照做反而会弄坏：

- **`line 70: arch: command not found`** —— Arch / CachyOS 的 coreutils **不提供** `/usr/bin/arch`。
  这是报错的根因，但 `spark-dwine-helper 5.8` 已改用 `get_arch=`uname -m``，新版不会再有这条。
- **"把 wrapper 第 27 行的 `$DISTRO` 判断改成 `command -v spark-box64`"** —— helper 5.8 包内全文
  grep 已无 `spark-box64` / `durapps` / wrapper 字样，该补丁**针对旧版、不适用**。
- **deb 下载 403** —— PKGBUILD 里的 `d.store.deepinos.org.cn` 已失效。可用的是星火商店 SDU 镜像
  `https://mirrors.sdu.edu.cn/spark-store/store/network/cn.quarkclouddrive.spark/`。
  单线程仅 14~250 KB/s，用 `aria2c -x16 -s16 -k1M --file-allocation=none` 约十分钟下完 150MB。

## 从源码构建

```bash
cd src
makepkg -f --noconfirm --nodeps --skippgpcheck
sudo pacman -U deepin-wine-quarkclouddrive-*.pkg.tar.zst
```

`--nodeps` 是必须的：三个 AUR 依赖得先装好，否则 makepkg 会因为缺依赖 `exit 8`。
依赖链：`spark-transhell` → `deepin-wine8-stable` → `spark-dwine-helper` → 本包。

构建小坑（都已在 `PKGBUILD` 里处理）：
- `deepin-wine8-stable` 的 `package()` 用相对路径 `ar -x deepin-wine8-stable_*.deb`，deb 必须放进 `src/`；
- 本包 `build()` 的 `bsdtar -xf "${srcdir}/data."*` 需要先 `cd src && bsdtar -xf *.deb`，
  并把 `deepin-wine-quarkclouddrive.sh` 与 `LICENSE.html` 一起 `cp` 进 `src/`；
- 重复构建时 `mv` 会把新目录塞进旧目录 → 包内多一份 144MB 重复文件。已加 `rm -rf` 保证幂等。

## 验证记录

| 场景 | 结果 |
|---|---|
| 命令行 `deepin-wine-quarkclouddrive` | ✅ |
| 应用菜单 / `gtk-launch deepin-wine-quarkclouddrive` | ✅ |
| 在带 `ELECTRON_RUN_AS_NODE=1` 的 IDE 终端里启动 | ✅（补丁生效） |
| 删光 bottle + 配置，模拟首次冷启动 | ✅ 自动建 bottle、自动定 2.0 缩放、不弹 zenity、只出现主窗口 |
| 日志中 `cd: C:/windows/command` 报错 | ✅ 已消失（计数 0） |
| `--no-sandbox` bad option | ✅ 已消失（不再传该参数） |

## 已知小尾巴（都不影响使用）

- `spark_get_tray_window` 会尝试连 `com.deepin.dde.TrayManager`，非 Deepin 桌面必然抛 `DBusException` —— 无害噪音。
- 日志里 `spark_kill.sh` 的 `xargs: 警告：选项 --max-lines 和 --replace 互斥`、若干
  `grep: stray \ before /`、`ERROR: Dangerous link path was ignored` 也都是无害噪音。
- 纯 Wayland + KDE 没有 XEmbed 托盘，托盘图标可能不显示；主窗口是 Electron 自绘，不受影响。
- `wqy-microhei` / `wqy-zenhei`（optdepends）在 Arch 官方仓库里没有，需要请装 AUR 版；
  有 Noto CJK 的话中文显示已正常。
- 如果之前用另一个 bottle 启动过（`Spark-QuarkCloudDrive`），`~/.deepinwine/` 下会有残留，可直接删。

## 致谢

上游 AUR 包维护者 **zxp19821005**，以及 deepin-wine / 星火商店（Spark Store）团队。
本仓库只做兼容性补丁，不分发任何夸克官方二进制；`LICENSE.html` 为上游附带。
夸克网盘本身是**闭源商业软件**，版权归夸克（UC / 阿里）所有，请遵守其用户协议。

## 相关

- AUR 包页面：https://aur.archlinux.org/packages/deepin-wine-quarkclouddrive
- 星火商店镜像（deb 来源）：https://mirrors.sdu.edu.cn/spark-store/
