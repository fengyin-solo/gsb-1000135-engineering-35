#!/usr/bin/env bash
# 前端 dev 启动 / 环境检查 / 依赖安装一体化脚本。
#
# 用法：
#   ./run.sh                环境检查 + 残留清理 + 启动 vite dev server（前台）
#   ./run.sh --install-only 只检查并安装依赖，不启动服务
#   ./run.sh --check        只做环境检查（依赖、端口、残留进程），输出结果后退出
#
# 覆盖的常见问题：
#   1. 依赖缺失 / node_modules 平台不匹配（例如从其他系统拷贝，rollup 原生模块缺失）
#   2. 端口被占用（vite 默认 strictPort 关闭会静默换端口，这里显式拦住）
#   3. 重复启动（残留的旧 dev server 进程）
set -euo pipefail
cd "$(dirname "$0")"

HOST="127.0.0.1"
PORT="${APP_PORT:-5173}"
PID_FILE=".vite.pid"
MODE="run"
case "${1:-}" in
  "") ;;
  --install-only) MODE="install" ;;
  --check) MODE="check" ;;
  *) echo "[frontend] 未知参数：$1（支持 --install-only / --check）" >&2; exit 2 ;;
esac

log()  { echo "[frontend] $*"; }
fail() { echo "[frontend] 错误：$*" >&2; exit 1; }

port_in_use() {
  CHECK_PORT="$PORT" node -e "const s=require('net').connect(Number(process.env.CHECK_PORT),'127.0.0.1');s.once('connect',()=>process.exit(0));s.once('error',()=>process.exit(1))"
}

# node_modules 存在且 rollup（含平台原生包）能加载才算依赖就绪
deps_ok() {
  [ -d node_modules ] && node -e "require('rollup')" >/dev/null 2>&1
}

stale_pid() {
  [ -f "$PID_FILE" ] || return 0
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "$pid"
  fi
}

stop_stale() {
  local pid
  pid="$(stale_pid)"
  if [ -n "$pid" ]; then
    log "发现残留的前端进程 (pid=$pid)，先停止再启动"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 25); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}

ensure_deps() {
  command -v node >/dev/null 2>&1 || fail "未找到 node，请先安装 Node.js 18 及以上版本"
  command -v npm  >/dev/null 2>&1 || fail "未找到 npm，请确认 Node.js 安装完整"
  if [ -d node_modules ] && ! deps_ok; then
    log "node_modules 与当前平台不匹配或已损坏（rollup 原生模块缺失），清理后重装"
    rm -rf node_modules package-lock.json
  fi
  if [ ! -d node_modules ]; then
    log "安装前端依赖（npm install）"
    npm install || fail "npm install 失败，请检查网络或 npm 镜像配置"
  fi
}

case "$MODE" in
  check)
    status=0
    if command -v node >/dev/null 2>&1; then
      log "node: $(node --version) / npm: $(npm --version 2>/dev/null || echo 缺失)"
    else
      log "node: 缺失（请先安装 Node.js 18+）"; status=1
    fi
    if deps_ok; then
      log "依赖: 就绪（node_modules 完整，rollup 原生包匹配当前平台）"
    else
      log "依赖: 未就绪（执行 ./run.sh --install-only 可自动修复）"
    fi
    pid="$(stale_pid)"
    if [ -n "$pid" ]; then
      log "进程: 有残留前端进程 (pid=$pid)，下次启动会自动接管"
    elif port_in_use; then
      log "进程: 端口 $PORT 被其他程序占用（需手动释放，或用 APP_PORT 换端口）"; status=1
    else
      log "进程: 端口 $PORT 空闲，无残留进程"
    fi
    exit "$status"
    ;;
  install)
    ensure_deps
    log "依赖安装完成"
    exit 0
    ;;
esac

# ---- run 模式 ----
ensure_deps
stop_stale
if port_in_use; then
  fail "端口 $PORT 已被其他程序占用，请先释放占用进程，或换端口启动：APP_PORT=5174 ./run.sh"
fi

log "启动前端 dev server http://$HOST:$PORT （/api 代理到后端，见 vite.config.ts）"
./node_modules/.bin/vite --host "$HOST" --port "$PORT" --strictPort &
pid=$!
echo "$pid" > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

wait "$pid"
