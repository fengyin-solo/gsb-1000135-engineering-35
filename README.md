# 实验室样品检测管理平台

面向检测实验室的样品接收、检测任务分配、仪器校准、试剂耗材、结果报告与质量审核的综合管理后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。
两边各自独立启动，前端 dev server 已关掉自动打开页面，启动后按终端打印的地址手工打开。

## 目录结构

```text
.
├── frontend/                 Vue 3 + Vite + TypeScript 前端
│   ├── src/views/            每个业务模块一个页面
│   ├── src/api/              统一请求封装
│   ├── src/stores/           会话与筛选状态
│   └── vite.config.ts        dev server 配置（open: false）
├── backend/                  FastAPI（Python） 后端
│   ├── app/routers/          每个业务模块一组接口
│   ├── app/services/         业务规则与状态流转
│   └── app/store.py          内存数据仓库与示例数据
├── .gitignore
└── docker-compose.yml
```

## 启动

### 一键命令（推荐）

```bash
make install   # 安装/修复前后端依赖（幂等，可重复执行）
make check     # 环境检查：python3/node、依赖完整性、端口占用、残留进程
make backend   # 启动后端（自动清理残留进程与过期缓存）
make frontend  # 启动前端 dev server
make build     # 前端生产构建（vue-tsc + vite build）
make stop      # 停止残留的前后端进程
make clean     # 深度清理：停进程 + 删除 .venv / node_modules / dist / 过期缓存
```

启动脚本自带自愈能力，覆盖三类常见本地问题：

- **依赖缺失/损坏**：`.venv` 或 `node_modules` 是从其他机器拷贝的残留（解释器路径失效、
  rollup 原生包平台不匹配）时，自动删除重建；系统缺 `python3-venv` 时自动走
  `--without-pip` + get-pip 引导。
- **端口占用**：启动前探测端口，被其他程序占用时给出明确提示，可用
  `APP_PORT=8001 ./run.sh` 换端口。
- **重复启动**：通过 pid 文件识别上次残留的进程并先停掉，避免旧进程持有过期的
  内存示例数据导致查询结果对不上。

### 后端

```bash
cd backend
./run.sh                # 检查环境 + 清理残留 + 启动
./run.sh --install-only # 只装依赖不启动
./run.sh --check        # 只做环境检查
./stop.sh               # 停止残留进程
```

健康检查：`curl http://127.0.0.1:8000/api/health`

### 前端

```bash
cd frontend
./run.sh                # 检查环境 + 清理残留 + 启动 dev server
./run.sh --install-only # 只装依赖不启动
./run.sh --check        # 只做环境检查
./stop.sh               # 停止残留进程
```

前端默认监听 `http://127.0.0.1:5173/`，dev server 不会自动打开浏览器，
需要自己访问。`/api` 由 vite 代理到后端 `http://127.0.0.1:8000`。

## 业务模块

| 模块 | 目录 | 业务对象 | 主要字段 |
| --- | --- | --- | --- |
| 样品接收 | `sample` | 检测样品 | 样品编号、样品名称、委托单位 |
| 检测任务 | `task` | 检测任务单 | 任务编号、所属样品、检测项目 |
| 仪器管理 | `instrument` | 检测仪器 | 仪器编号、仪器名称、型号规格 |
| 校准记录 | `calibration` | 校准记录单 | 记录编号、仪器编号、校准机构 |
| 试剂耗材 | `reagent` | 试剂耗材 | 试剂编号、试剂名称、规格等级 |
| 检测结果 | `result` | 检测结果 | 结果编号、所属任务、检测项 |
| 检测报告 | `report` | 检测报告 | 报告编号、委托单位、样品名称 |
| 质量控制 | `qc` | 质控样品 | 质控编号、质控类别、标准值 |
| 偏离处理 | `deviation` | 偏离记录 | 偏离编号、偏离描述、涉及样品 |
| 样品留存 | `sample_storage` | 留存样品 | 留存编号、样品编号、留存位置 |
| 委托合同 | `contract` | 委托检验合同 | 合同编号、委托单位、联系人 |
| 检测人员 | `staff` | 检测员 | 员工编号、姓名、技术职称 |
| 检测方法 | `method` | 检测方法 | 方法编号、方法名称、适用标准 |
| 环境监测 | `environment` | 环境记录 | 记录编号、监测区域、温度值 |
| 客户申诉 | `complain` | 申诉记录 | 申诉编号、申诉单位、涉及报告 |
| 内审管理 | `audit` | 内审记录 | 内审编号、审核范围、审核组长 |
| 仪器维修 | `equipment_repair` | 维修记录 | 维修编号、仪器编号、故障描述 |
| 体系文档 | `document` | 体系文档 | 文档编号、文档名称、文档类型 |

## 约定

- 每个模块的前端页面在 `frontend/src/views/<模块>/index.vue`，后端接口在
  `backend/app/routers/<模块>.py`，业务规则在 `backend/app/services/<模块>.py`。
- 列表接口统一返回 `{ items, total, page, size }`，动作接口统一返回 `{ ok, message }`。
- 状态流转只允许在 `app/services` 里改，路由层不做业务判断。
