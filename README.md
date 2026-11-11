# 夸克网盘（deepin-wine-quarkclouddrive）Arch/CachyOS 修复版

装好的东西 + 为什么原版装不上/起不来 + 怎么在别的机器上复现。

## 当前状态（本机已装好，可直接用）

```
deepin-wine-quarkclouddrive 3.2.6spark4-4   （修复版，pkgrel 4）
deepin-wine8-stable         8.16deepin25_1-1
spark-dwine-helper          5.8_5.3.14-1
spark-transhell             1.1-5
```

启动方式（任选）：
- 应用菜单里点「夸克网盘」
- 终端执行 `deepin-wine-quarkclouddrive`

已实测：应用菜单启动 / 终端启动两条路径都能正常开出登录窗口（扫码登录页渲染完整，2.0 缩放正确）。

## 原版为什么失败 —— 四个互相独立的 bug

### 1. `--no-sandbox` 直接把程序打死（致命）
AUR 的 PKGBUILD 里有一句 sed，硬把 desktop 的 Exec 改成 `deepin-wine-quarkclouddrive --no-sandbox`：

```
s|"/opt/apps/${pkgname}/files/run.sh"|${pkgname} --no-sandbox|g
```

但 QuarkCloudDrive.exe 用的是夸克自研的命令行解析器，不认这个参数：

```
QuarkCloudDrive.exe: bad option: --no-sandbox    →  RC=9，立刻退出
```

（exe 里能直接 grep 到 "bad option" 字符串；`--no-sandbox=1`、`--enable-logging` 同样被拒。）
Electron 的渲染进程本来就会自己带 `--no-sandbox`，根本不需要外部传。
**修法：删掉这个 sed。**

### 2. `ELECTRON_RUN_AS_NODE` 导致"启动两秒后静默退出"（最阴的一个）
夸克网盘本身是 Electron 应用。如果父进程注入了 `ELECTRON_RUN_AS_NODE=1`，
它会以"纯 Node 解释器"模式运行 —— 主进程脚本跑完就 `exit(0)`，不建窗口、不打日志、没有崩溃码。

用 VS Code / Cursor / 各类 Electron IDE 的集成终端启动时必然踩到。本机 DSH 会话 shell 里也带着这个变量
（`/proc/<pid>/environ` 可见，plasmashell / PID 1 没有），所以一开始怎么 strace 都查不出崩溃点 —— 它不是崩溃，是正常退出。

**修法：启动脚本里 `unset ELECTRON_RUN_AS_NODE ELECTRON_NO_ATTACH_CONSOLE`（在 /usr/bin 包装脚本 + run.sh + spark 钩子三处都做）。**

### 3. zenity 缩放对话框卡死首次启动
`spark_run_v4.sh` → `set-wine-scale.sh` → 没找到 `$WINEPREFIX/scale.txt` 时调 `get-scale.sh`，
后者弹出 `zenity --list`（宽 700 高 350，让你手选 1.0~4.0 缩放）。
从自启动 / 脚本 / 无人值守场景启动时会**永久卡在这个弹窗**上，看起来就是"装好了但打不开"。

**修法：首次启动时按系统 `Xft.dpi` 自动推导缩放档位写进 `~/.config/spark-wine/scale.txt`，完全不弹窗。**
本机 `xrdb -query | grep Xft.dpi` = 192、屏幕 2880x1800 → 自动算出 2.0（对应 Windows 192 dpi）。
实测：删掉 scale.txt 冷启动，自动生成 2.0，zenity 进程数 0，窗口正常。

### 4. `cd: C:/windows/command: 没有那个文件或目录`（AUR 评论里那条报错）
`spark_run_v4.sh` 的 CallProcess 里：

```bash
path=$(echo ${path/c:/${WINEPREFIX}/drive_c})   # 只替换小写 c:
```

而 lnk 分支传进去的是大写 `C:/windows/command/start.exe` → 替换失败 → `cd` 到不存在的路径 → 退回 $HOME 启动（污染工作目录）。
**修法：把小写 `c:` 传进去，并在 spark 钩子里再兜一层大小写归一。**

### 附：AUR 评论里那条 `arch: command not found` / `spark-box64`
- Arch/CachyOS 的 coreutils **不提供** `/usr/bin/arch`，这就是 `line 70: arch: command not found` 的根因；
- 但 spark-dwine-helper 5.8 已经改用 `get_arch=`uname -m``，且包内全文 grep 无 `spark-box64`/`durapps`/wrapper 字样。

所以评论区那个改 `deepin-wine8-stable` wrapper 第 27 行、加 spark-box64 判断的补丁**针对的是旧版，新版不需要**，照做反而可能弄坏。

### 附：deb 下载 403
PKGBUILD 里的 `d.store.deepinos.org.cn` 已不可用，现在能下的是星火商店 SDU 镜像：
`https://mirrors.sdu.edu.cn/spark-store/store/network/cn.quarkclouddrive.spark/cn.quarkclouddrive.spark_3.2.6spark4_all.deb`
（150036032 字节，sha256 `1f01a60ff524d214f0e53a0b61a828263306e9748528c132637325010d67e425`）。
单线程只有 14~250 KB/s，用 `aria2c -x16 -s16 -k1M --file-allocation=none` 十分钟下完。

## 目录内容

```
pkg/     四个 .pkg.tar.zst，可直接 pacman -U 安装（本机用的就是这几个）
src/     修复版 PKGBUILD + 三个补丁文件（重建用）
```

## 在别的机器上装

```bash
# 方式 A：直接用我构建好的包
sudo pacman -U pkg/spark-transhell-1.1-5-x86_64.pkg.tar.zst \
               pkg/deepin-wine8-stable-8.16deepin25_1-1-x86_64.pkg.tar.zst \
               pkg/spark-dwine-helper-5.8_5.3.14-1-any.pkg.tar.zst \
               pkg/deepin-wine-quarkclouddrive-3.2.6spark4-4-x86_64.pkg.tar.zst

# 方式 B：自己重建（pkg/ 里缺 deb，需要联网；--nodeps 必须有）
cd src && makepkg -f --noconfirm --nodeps --skippgpcheck && sudo pacman -U *.pkg.tar.zst
```

构建注意：全部三个 AUR 包都得加 `--nodeps`，否则 makepkg 因缺依赖 exit 8。

## 修复都改在哪（想自己动手的话）

| 文件 | 改动 |
|---|---|
| `PKGBUILD` | 删掉注入 `--no-sandbox` 的 sed；desktop 的 Exec 改指 `deepin-wine-quarkclouddrive`；顺手修 run.sh 的小写盘符 + unset ELECTRON_*；打包 spark 钩子 |
| `src/deepin-wine-quarkclouddrive.sh` → `/usr/bin/deepin-wine-quarkclouddrive` | exec 前 unset `ELECTRON_RUN_AS_NODE`/`ELECTRON_NO_ATTACH_CONSOLE`；`C:/windows/...` 改 `c:/windows/...` |
| `src/Deepin-QuarkCloudDrive.sh` → `/opt/deepinwine/tools/spark_run_v4_app_configs/Deepin-QuarkCloudDrive.sh` | spark_run_v4.sh 的官方扩展钩子：① unset ELECTRON_*；② 自动推导缩放写 scale.txt；③ 盘符大小写归一 |
| `/usr/share/applications/deepin-wine-quarkclouddrive.desktop` | `Exec=deepin-wine-quarkclouddrive -u %u`（不再走 deb 里 BOTTLENAME=Spark-QuarkCloudDrive 的 run.sh） |

第 3 条用的是 spark-dwine-helper 官方设计的扩展点：`spark_run_v4.sh` 的 CallApp 会优先 source
`/opt/deepinwine/tools/spark_run_v4_app_configs/${BOTTLENAME}.sh`，没有才走通用启动。所以补丁不打在 helper 自身，不会被 helper 升级冲掉。

## 已知小尾巴（都不影响使用）

- `spark_get_tray_window` 会尝试连 `com.deepin.dde.TrayManager`，非 Deepin 桌面必然抛 DBusException —— 无害噪音。
- 日志里 `spark_kill.sh` 的 `xargs: 警告：选项 --max-lines 和 --replace 互斥`、若干 `grep: stray \ before /`、`ERROR: Dangerous link path was ignored` 也都是无害噪音。
- 纯 Wayland + KDE 下没有 XEmbed 托盘，托盘图标可能不显示；主窗口是 Electron 自绘，不受影响。
- `wqy-microhei` / `wqy-zenhei`（optdepends）在 Arch 官方仓库里没有，需要就装 AUR 版；本机已有 Noto CJK，中文显示正常。

## 本机验证记录

| 场景 | 结果 |
|---|---|
| 命令行 `deepin-wine-quarkclouddrive` | ✅ 正常出窗口 |
| 应用菜单 / `gtk-launch deepin-wine-quarkclouddrive` | ✅ 正常出窗口 |
| 在带 `ELECTRON_RUN_AS_NODE=1` 的 IDE 终端里启动 | ✅ 正常出窗口（补丁生效） |
| 删光 bottle + 配置，模拟首次冷启动 | ✅ 自动建 bottle、自动定 2.0 缩放、不弹 zenity、只出现主窗口 |
| 日志中 `cd: C:/windows/command` 报错 | ✅ 已消失（计数 0） |
| `--no-sandbox` bad option | ✅ 已消失（不再传该参数） |
