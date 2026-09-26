#!/usr/bin/env bash
# 后端启动 / 环境检查 / 依赖安装一体化脚本。
#
# 用法：
#   ./run.sh                环境检查 + 残留清理 + 启动 uvicorn（前台）
#   ./run.sh --install-only 只检查并安装依赖，不启动服务
#   ./run.sh --check        只做环境检查（依赖、端口、残留进程），输出结果后退出
#
# 覆盖的常见问题：
#   1. 依赖缺失 / .venv 损坏（例如从其他机器拷贝，解释器路径失效）
#   2. 端口被占用（上次启动失败残留的进程或别的程序）
#   3. 重复启动（旧进程持有过期的内存示例数据，导致查询结果对不上）
set -euo pipefail
cd "$(dirname "$0")"

HOST="${APP_HOST:-127.0.0.1}"
PORT="${APP_PORT:-8000}"
PID_FILE=".uvicorn.pid"
MODE="run"
case "${1:-}" in
  "") ;;
  --install-only) MODE="install" ;;
  --check) MODE="check" ;;
  *) echo "[backend] 未知参数：$1（支持 --install-only / --check）" >&2; exit 2 ;;
esac

log()  { echo "[backend] $*"; }
fail() { echo "[backend] 错误：$*" >&2; exit 1; }

# 端口是否已被监听（用 python 探测，避免依赖 ss/lsof 等外部命令）
port_in_use() {
  python3 - "$HOST" "$PORT" <<'PY'
import socket, sys
host = "127.0.0.1" if sys.argv[1] in ("0.0.0.0", "::") else sys.argv[1]
s = socket.socket()
s.settimeout(0.5)
sys.exit(0 if s.connect_ex((host, int(sys.argv[2]))) == 0 else 1)
PY
}

venv_ok() { [ -x .venv/bin/python ] && .venv/bin/python --version >/dev/null 2>&1; }
pip_ok()  { venv_ok && .venv/bin/python -m pip --version >/dev/null 2>&1; }
deps_ok() { pip_ok && .venv/bin/python -c "import fastapi, uvicorn" >/dev/null 2>&1; }

# pid 文件中记录的、仍在运行的进程号；没有则输出空
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
    log "发现残留的后端进程 (pid=$pid)，先停止再启动，避免旧进程返回过期示例数据"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 25); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}

# 用 get-pip.py 给没有 pip 的虚拟环境引导 pip（系统缺 ensurepip 时的兜底）
bootstrap_pip() {
  command -v curl >/dev/null 2>&1 || return 1
  local get_pip
  get_pip="$(mktemp)"
  curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$get_pip" || { rm -f "$get_pip"; return 1; }
  .venv/bin/python "$get_pip" -q || { rm -f "$get_pip"; return 1; }
  rm -f "$get_pip"
}

# 创建虚拟环境；系统缺 ensurepip（未装 python3-venv）时走 --without-pip + get-pip 引导
create_venv() {
  if python3 -m venv .venv 2>/dev/null && pip_ok; then
    return 0
  fi
  log "python3 -m venv 直接创建失败（可能缺 python3-venv/ensurepip），尝试 --without-pip 方式"
  rm -rf .venv
  python3 -m venv --without-pip .venv || return 1
  pip_ok || bootstrap_pip
}

ensure_deps() {
  command -v python3 >/dev/null 2>&1 || fail "未找到 python3，请先安装 Python 3.10 及以上版本"
  if [ -d .venv ] && ! venv_ok; then
    log "检测到损坏的 .venv（解释器不可用，可能是从其他机器拷贝的残留），删除后重建"
    rm -rf .venv
  fi
  if [ ! -d .venv ]; then
    log "创建虚拟环境 .venv"
    create_venv || fail "虚拟环境创建失败，请安装 python3-venv 后重试（Debian/Ubuntu: apt install python3-venv）"
  fi
  if ! pip_ok; then
    log "虚拟环境缺少 pip（可能是上次创建中断的残留），引导安装 pip"
    bootstrap_pip || fail "pip 引导失败，请删除 backend/.venv 后重试，或安装 python3-venv"
  fi
  if ! deps_ok; then
    log "安装后端依赖（requirements.txt）"
    .venv/bin/python -m pip install -q -r requirements.txt || fail "依赖安装失败，请检查网络或 requirements.txt"
  fi
}

case "$MODE" in
  check)
    status=0
    if command -v python3 >/dev/null 2>&1; then
      log "python3: $(python3 --version 2>&1)"
    else
      log "python3: 缺失（请先安装 Python 3.10+）"; status=1
    fi
    if deps_ok; then
      log "依赖: 就绪（.venv 可导入 fastapi / uvicorn）"
    else
      log "依赖: 未就绪（执行 ./run.sh --install-only 可自动修复）"
    fi
    pid="$(stale_pid)"
    if [ -n "$pid" ]; then
      log "进程: 有残留后端进程 (pid=$pid)，下次启动会自动接管"
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
  fail "端口 $PORT 已被其他程序占用，请先释放占用进程，或换端口启动：APP_PORT=8001 ./run.sh"
fi

# 清理其他 Python 版本生成的过期字节码，避免缓存与当前代码对不上
find app -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

log "启动后端 http://$HOST:$PORT"
.venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT" &
pid=$!
echo "$pid" > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

ready=0
for _ in $(seq 1 50); do
  kill -0 "$pid" 2>/dev/null || fail "uvicorn 启动失败，请查看上方日志"
  if .venv/bin/python - "$HOST" "$PORT" <<'PY'
import json, sys, urllib.request
host = "127.0.0.1" if sys.argv[1] in ("0.0.0.0", "::") else sys.argv[1]
try:
    with urllib.request.urlopen(f"http://{host}:{sys.argv[2]}/api/health", timeout=1) as resp:
        sys.exit(0 if json.load(resp).get("ok") else 1)
except Exception:
    sys.exit(1)
PY
  then
    ready=1
    break
  fi
  sleep 0.2
done
[ "$ready" = "1" ] || fail "健康检查未通过，服务未就绪"
log "后端已就绪，仪器维修查询入口: http://$HOST:$PORT/api/equipment_repair"

wait "$pid"
