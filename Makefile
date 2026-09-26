.PHONY: install check backend frontend build stop clean

# 安装前后端依赖（幂等：自动修复损坏的 .venv / node_modules）
install:
	cd backend && ./run.sh --install-only
	cd frontend && ./run.sh --install-only

# 环境检查：python3/node、依赖完整性、端口占用与残留进程
check:
	cd backend && ./run.sh --check
	cd frontend && ./run.sh --check

# 启动后端（自动清理残留进程与过期缓存后再拉起）
backend:
	cd backend && ./run.sh

# 启动前端 dev server（自动清理残留进程后再拉起）
frontend:
	cd frontend && ./run.sh

# 前端生产构建（先确保依赖可用，再 vue-tsc + vite build）
build:
	cd frontend && ./run.sh --install-only && npm run build

# 停止残留的前后端进程
stop:
	cd backend && ./stop.sh
	cd frontend && ./stop.sh

# 深度清理：停进程 + 删除依赖目录、构建产物与过期缓存，之后需重新 make install
clean: stop
	rm -rf backend/.venv frontend/node_modules frontend/dist frontend/package-lock.json
	find backend/app -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
