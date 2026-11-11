#!/bin/bash
# Deepin-QuarkCloudDrive.sh
# spark_run_v4.sh 的专属 APP 配置钩子（CallApp 会 source 本文件，优先于通用启动）。
# 由 deepin-wine-quarkclouddrive-fix 提供。
# 作用：在真正调用 wine 之前，修掉三处会让夸克网盘启动失败/卡死/刷屏的问题。

# ---------- 修复 1：ELECTRON_RUN_AS_NODE 必须剔除 ----------
# 夸克网盘是 Electron 应用。若父进程（VS Code / Cursor / DSH / 某些 CI 工具）
# 注入了 ELECTRON_RUN_AS_NODE=1，exe 会以 Node 解释器模式启动、执行完即 exit(0)，
# 不建窗口、不打日志，看起来就是"秒退"。
unset ELECTRON_RUN_AS_NODE
unset ELECTRON_NO_ATTACH_CONSOLE

# ---------- 修复 2：自动生成缩放配置，避免 zenity 阻塞 ----------
# set-wine-scale.sh -> get-scale.sh 在没有 ~/.config/spark-wine/scale.txt 时会用
# zenity --list 让用户手选缩放；非交互启动（自启动、桌面点击、CI）会永久阻塞。
# 这里按系统 Xft.dpi 自动推导一个合法档位写进去。
_scale_file="$HOME/.config/spark-wine/scale.txt"
if [ ! -f "$_scale_file" ]; then
    mkdir -p "$HOME/.config/spark-wine"
    _dpi=$(xrdb -query 2>/dev/null | awk '/^Xft\.dpi:/{print int($2); exit}')
    [ -z "$_dpi" ] && _dpi=$(kreadconfig6 --file kdeglobals --group Xft --key dpi 2>/dev/null | tr -dc '0-9')
    [ -z "$_dpi" ] && _dpi=96
    _s=$(awk -v d="$_dpi" 'BEGIN{s=d/96; split("1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0",a," "); best=a[1]; bd=1e9; for(i in a){x=a[i]; dd=(x>s?x-s:s-x); if(dd<bd){bd=dd;best=x}} printf "%s", best}')
    echo "$_s" > "$_scale_file"
    echo "[fix] 自动检测缩放: $_dpi dpi -> $_s"
fi
[ -d "$WINEPREFIX" ] && [ ! -f "$WINEPREFIX/scale.txt" ] && cp -f "$_scale_file" "$WINEPREFIX/scale.txt" 2>/dev/null

# ---------- 修复 3：路径盘符改成小写，让 spark_run_v4.sh 能正确 cd ----------
# CallProcess 里 path=\${path/c:/\${WINEPREFIX}/drive_c} 只替换小写 c:，
# 而 lnk 分支传进来的是大写 "C:/windows/command/start.exe"，
# 于是 "cd: C:/windows/command: 没有那个文件或目录" 并退回到 $HOME 启动。
_arg1="${1}"
case "$_arg1" in
    [Cc]:*) _arg1="c${_arg1:1}" ;;
esac

CallProcess "$_arg1" "${@:2}"
