#!/usr/bin/env bash
# 停止残留的前端 dev server 进程并清理 pid 文件。
set -euo pipefail
cd "$(dirname "$0")"

PID_FILE=".vite.pid"

if [ -f "$PID_FILE" ]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "[frontend] 停止前端进程 (pid=$pid)"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 25); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
  else
    echo "[frontend] pid 文件存在但进程已退出，清理文件"
  fi
  rm -f "$PID_FILE"
else
  echo "[frontend] 没有 pid 文件，跳过前端进程清理"
fi

# 兜底：停掉没有 pid 文件记录的本项目 vite 进程。
# 模式锚定到命令行开头（node ./node_modules/.bin/vite），避免误杀只是在命令行里提到该路径的无关进程。
if command -v pkill >/dev/null 2>&1; then
  pkill -f "^node \./node_modules/\.bin/vite" 2>/dev/null || true
fi

echo "[frontend] 清理完成"
