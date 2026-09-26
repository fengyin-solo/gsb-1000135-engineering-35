#!/usr/bin/env bash
# 后端启动脚本：先做环境自检与残留清理，再启动服务。
#   ./run.sh          自检通过后启动 uvicorn
#   ./run.sh --check  只做环境自检与清理，不启动服务（供 make check 使用）
set -euo pipefail
cd "$(dirname "$0")"

HOST="${BACKEND_HOST:-127.0.0.1}"
PORT="${BACKEND_PORT:-8000}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

log() { printf '[backend] %s\n' "$*"; }
fail() { printf '[backend] 错误：%s\n' "$*" >&2; exit 1; }

# --- 1. 清理过期缓存：陈旧 __pycache__ 可能装着旧版本的示例数据/代码 ---
find app -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

# --- 2. 校验虚拟环境：解释器必须能跑、关键依赖必须能导入 ---
#    从别的机器拷贝来的 .venv（软链指向别的路径、Python 版本不同）会被判定为损坏并重建。
venv_ok() {
  [ -x .venv/bin/python ] && \
  .venv/bin/python -c "import fastapi, uvicorn, pydantic" >/dev/null 2>&1
}

if ! venv_ok; then
  log "虚拟环境缺失或已损坏（可能来自其他机器或其他 Python 版本），重新创建…"
  rm -rf .venv
  if ! python3 -m venv .venv 2>/dev/null; then
    # 某些系统缺 ensurepip（如 Debian 未装 python3-venv），退回 --without-pip 再引导 pip
    rm -rf .venv
    python3 -m venv --without-pip .venv \
      || fail "无法创建虚拟环境，请确认 python3 可用"
  fi
  if [ ! -x .venv/bin/pip ]; then
    log "venv 内没有 pip，引导安装…"
    .venv/bin/python -m ensurepip 2>/dev/null || {
      curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
        && .venv/bin/python /tmp/get-pip.py -q
    } || fail "pip 引导失败，请检查网络或手动安装 python3-venv"
  fi
fi

.venv/bin/pip install -q -r requirements.txt || fail "依赖安装失败，请检查网络后重试"
venv_ok || fail "依赖安装后仍无法导入 fastapi/uvicorn，请执行 make clean 后重试"

# --- 3. 端口与重复启动检查 ---
if curl -fsS --max-time 2 "http://$HOST:$PORT/api/health" 2>/dev/null | grep -q '"ok":true'; then
  log "后端已在 http://$HOST:$PORT 运行（上次启动的进程仍在），跳过重复启动。"
  exit 0
fi

if ! .venv/bin/python - "$HOST" "$PORT" <<'PY'
import socket, sys
s = socket.socket()
# 与 uvicorn 行为一致：SO_REUSEADDR，避免把 TIME_WAIT 误判为端口占用
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind((sys.argv[1], int(sys.argv[2])))
except OSError:
    sys.exit(1)  # 端口被占用
else:
    sys.exit(0)  # 端口空闲
finally:
    s.close()
PY
then
  fail "端口 $PORT 被其他进程占用。若是上次失败残留的进程，请先执行 make stop；否则用 BACKEND_PORT 换端口。"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  log "环境自检通过：venv 正常、依赖齐全、端口 $PORT 空闲。"
  exit 0
fi

log "启动后端：http://$HOST:$PORT （健康检查 /api/health）"
exec .venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT"
