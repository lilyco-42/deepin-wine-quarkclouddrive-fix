#!/bin/bash
set -e
BOTTLENAME=Deepin-QuarkCloudDrive
APPVER=3.2.6spark4
# NOTE(cachyos-fix): 必须用小写 c: ，spark_run_v4.sh 的 CallProcess 只做
# ${path/c:/\${WINEPREFIX}/drive_c} 的小写替换；大写 C: 会导致
# "cd: C:/windows/command: 没有那个文件或目录" 并污染工作目录。
EXEC_PATH="c:/ProgramData/Microsoft/Windows/Start Menu/Programs/夸克网盘.lnk"
START_SHELL_PATH="/opt/deepinwine/tools/spark_run_v4.sh"
export MIME_TYPE=""
export DEB_PACKAGE_NAME=deepin-wine-quarkclouddrive
export APPRUN_CMD=deepin-wine8-stable
EXPORT_ENVS=""
export SPECIFY_SHELL_DIR=`dirname ${START_SHELL_PATH}`
ARCHIVE_FILE_DIR="/opt/apps/${DEB_PACKAGE_NAME}/files"
export WINEDLLPATH="/opt/${APPRUN_CMD}/lib:/opt/${APPRUN_CMD}/lib64"
export WINEPREDLL="${ARCHIVE_FILE_DIR}/dlls"
DISABLE_ATTACH_FILE_DIALOG=""
if [ -z "${DISABLE_ATTACH_FILE_DIALOG}" ];then
    export ATTACH_FILE_DIALOG=1
fi
if [ -n "$EXPORT_ENVS" ];then
    export "${EXPORT_ENVS}"
fi

# ==== cachyos-fix: Electron 应用禁止继承 ELECTRON_RUN_AS_NODE ====
# VS Code / Cursor / DSH 等 Electron 系程序的集成终端会向子进程注入
# ELECTRON_RUN_AS_NODE=1。夸克网盘本身是 Electron 应用，继承该变量后会以
# "纯 Node 模式" 运行 —— 主进程脚本执行完立刻 exit(0)，不创建任何窗口，
# 表现为"启动约 2 秒后静默退出、无报错、无日志"。
unset ELECTRON_RUN_AS_NODE
unset ELECTRON_NO_ATTACH_CONSOLE

if [ -n "${EXEC_PATH}" ];then
    if [ -z "${EXEC_PATH##*.lnk*}" ];then
        exec "${START_SHELL_PATH}" "${BOTTLENAME}" "${APPVER}" "c:/windows/command/start.exe" "/Unix" "${EXEC_PATH}" "$@" || exit $?
    else
        exec "${START_SHELL_PATH}" "${BOTTLENAME}" "${APPVER}" "${EXEC_PATH}" "$@" || exit $?
    fi
else
    exec "${START_SHELL_PATH}" "${BOTTLENAME}" "${APPVER}" "uninstaller.exe" "$@" || exit $?
fi
