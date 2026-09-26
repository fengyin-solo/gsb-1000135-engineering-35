.PHONY: install backend frontend check stop clean

install:
	cd backend && ./run.sh --check
	cd frontend && npm install

backend:
	cd backend && ./run.sh

frontend:
	cd frontend && npm run dev

# 环境自检：不启动服务，只验证依赖、端口可用
check:
	cd backend && ./run.sh --check
	cd frontend && node scripts/check-env.mjs --build

# 清理上次失败残留的进程（端口 8000/5173 上的 uvicorn / vite）
# 模式里用 [u]/[v] 是为了不让 pkill 匹配到执行这条命令的 shell 自己
stop:
	@-pkill -f "[u]vicorn app.main:app" 2>/dev/null && echo "已停止残留的后端进程" || true
	@-pkill -f "node_modules/(\.bin/)?[v]ite" 2>/dev/null && echo "已停止残留的前端进程" || true
	@echo "残留进程清理完成"

# 深度清理：停进程 + 删除虚拟环境、node_modules、构建产物与缓存
clean: stop
	rm -rf backend/.venv frontend/node_modules frontend/dist frontend/node_modules/.vite
	find backend/app -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
	@echo "清理完成，可执行 make install 重新安装"
