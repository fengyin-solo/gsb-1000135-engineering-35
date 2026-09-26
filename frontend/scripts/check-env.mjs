// 前端启动/构建前的环境自检：
//   node scripts/check-env.mjs          dev 模式：依赖完整性 + 端口占用检查
//   node scripts/check-env.mjs --build  构建模式：只查依赖完整性，不查端口
//
// 背景：node_modules 若从别的机器/平台拷贝（或上次安装中断），会缺当前平台的
// rollup 原生绑定（如 @rollup/rollup-linux-arm64-gnu），表现为启动即崩溃；
// 上次失败残留的 dev server 会占住 5173，让本次启动静默漂移到别的端口。
import { execSync } from 'node:child_process'
import net from 'node:net'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const root = fileURLToPath(new URL('..', import.meta.url))
const isBuild = process.argv.includes('--build')
const PORT = Number(process.env.FRONTEND_PORT ?? 5173)
const HOST = '127.0.0.1'

const log = (msg) => console.log(`[frontend] ${msg}`)
const fail = (msg) => {
  console.error(`[frontend] 错误：${msg}`)
  process.exit(1)
}

// --- 1. Node 版本 ---
const major = Number(process.versions.node.split('.')[0])
if (major < 18) {
  fail(`Node.js 版本过低（当前 ${process.versions.node}），需要 >= 18`)
}

// --- 2. 依赖完整性：关键包不仅要存在，还要能真正加载（覆盖原生绑定缺失） ---
function depsHealthy() {
  for (const pkg of ['vue', 'vue-router', 'pinia', 'vite', '@vitejs/plugin-vue', 'rollup']) {
    try {
      require(pkg)
    } catch {
      return false
    }
  }
  return true
}

if (!depsHealthy()) {
  log('依赖缺失或已损坏（可能是跨平台拷贝或上次安装中断），重新安装…')
  try {
    execSync('rm -rf node_modules', { cwd: root, stdio: 'inherit' })
    execSync('npm install', { cwd: root, stdio: 'inherit' })
  } catch {
    fail('依赖重装失败，请检查网络后执行 make clean && make install')
  }
  if (!depsHealthy()) {
    fail('依赖重装后仍无法加载，请执行 make clean && make install')
  }
  log('依赖已修复')
}

// --- 3. 端口占用检查（仅 dev 模式）：避免残留进程让本次启动静默换端口 ---
if (!isBuild) {
  const occupied = await new Promise((resolve) => {
    const socket = net.connect({ host: HOST, port: PORT })
    socket.once('connect', () => {
      socket.destroy()
      resolve(true)
    })
    socket.once('error', () => resolve(false))
  })
  if (occupied) {
    fail(
      `端口 ${PORT} 已被占用，可能是上次失败残留的 dev server。` +
      '请先执行 make stop 清理，或确认旧进程已退出后重试。',
    )
  }
}

log('环境自检通过')
