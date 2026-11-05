#!/bin/zsh
# Finder 双击运行；默认升级现有 MotoNav，不自动进行完整安装。
task_root="${0:A:h}"
/usr/bin/python3 "$task_root/firmware/flash_macos.py" "$@"
task_result=$?
if [[ -t 0 ]]; then
  read "?按回车关闭窗口…"
fi
exit "$task_result"
