#!/usr/bin/env bash
# 停止残留的后端进程并清理运行期文件（pid 文件、过期字节码缓存）。
set -euo pipefail
cd "$(dirname "$0")"

PID_FILE=".uvicorn.pid"

if [ -f "$PID_FILE" ]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "[backend] 停止后端进程 (pid=$pid)"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 25); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
  else
    echo "[backend] pid 文件存在但进程已退出，清理文件"
  fi
  rm -f "$PID_FILE"
else
  echo "[backend] 没有 pid 文件，跳过后端进程清理"
fi

# 兜底：停掉没有 pid 文件记录的同名 uvicorn 进程（例如旧版 run.sh 启动的）。
# 模式锚定到命令行中的 "bin/uvicorn app.main:app"，避免误杀只是在命令行里提到该名字的无关进程。
if command -v pkill >/dev/null 2>&1; then
  pkill -f "bin/uvicorn app\.main:app" 2>/dev/null || true
fi

find app -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
echo "[backend] 清理完成"
