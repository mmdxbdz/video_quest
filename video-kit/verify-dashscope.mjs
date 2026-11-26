#!/usr/bin/env node
/**
 * 通义万相 / DashScope 视频生成 —— 最小验证脚本
 * 目标：确认 1) key 能用 2) 视频模型开通了没 3) 生成一条 5 秒视频要多久多少钱
 *
 * 无需安装任何依赖（Node 22+ 自带 fetch）
 *
 * 用法：
 *   node verify-dashscope.mjs --check                 # 只验 key 是否可用
 *   node verify-dashscope.mjs --prompt "深夜街道，薄雾，缓慢推镜"
 *   node verify-dashscope.mjs --prompt "..." --model wan3.0-video --size 720*1280
 *   node verify-dashscope.mjs --prompt "..." --image https://公网可访问的首帧图.jpg
 *
 * 当模型参数结构与默认不同（新模型常见），用透传：
 *   --params '{"resolution":"720P","prompt_extend":true}'   # 合并进 parameters
 *   --input  '{"img_url":"https://..."}'                     # 合并进 input
 *   --show                                                   # 只打印请求体，不提交
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const DEFAULT_BASE = 'https://dashscope.aliyuncs.com/api/v1'
const VIDEO_PATH = '/services/aigc/video-generation/video-synthesis'

// 把用户粘进来的各种地址（含 .../compatible-mode/v1）规整成 /api/v1
function normalizeBase(raw) {
  let s = String(raw || '').trim()
  if (!s) return DEFAULT_BASE
  if (!/^https?:\/\//.test(s)) s = 'https://' + s
  s = s.replace(/\/+$/, '')
  for (const suffix of ['/compatible-mode/v1', '/compatible-mode']) {
    if (s.endsWith(suffix)) { s = s.slice(0, -suffix.length); break }
  }
  if (s.endsWith('/api/v1')) return s
  if (s.includes('/api/v1/')) return s.slice(0, s.indexOf('/api/v1/') + '/api/v1'.length)
  return s + '/api/v1'
}

function rootOf(base) {
  return base.endsWith('/api/v1') ? base.slice(0, -'/api/v1'.length) : base
}

let BASE = DEFAULT_BASE
let COMPAT = rootOf(DEFAULT_BASE) + '/compatible-mode/v1/chat/completions'

function parseArgs(argv) {
  const o = {
    model: 'wan3.0-video',
    prompt: '',
    image: '',
    size: '1280*720',
    duration: 5,
    timeoutMin: 25,
    outDir: 'out',
    check: false,
    quiet: false,
    paramsJson: '',
    inputJson: '',
    show: false,
    base: '',
    key: '',
    diag: false,
  }
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i]
    const next = () => argv[++i]
    if (a === '--model') o.model = next()
    else if (a === '--prompt') o.prompt = next()
    else if (a === '--image') o.image = next()
    else if (a === '--size') o.size = next()
    else if (a === '--duration') o.duration = Number(next())
    else if (a === '--timeout') o.timeoutMin = Number(next())
    else if (a === '--out') o.outDir = next()
    else if (a === '--check') o.check = true
    else if (a === '--quiet') o.quiet = true
    else if (a === '--params') o.paramsJson = next()
    else if (a === '--input') o.inputJson = next()
    else if (a === '--show') o.show = true
    else if (a === '--base') o.base = next()
    else if (a === '--key') o.key = next()
    else if (a === '--diag') o.diag = true
  }
  return o
}

async function loadKey(cliKey) {
  if (cliKey && cliKey.trim()) return cliKey.trim()
  if (process.env.DASHSCOPE_API_KEY) return process.env.DASHSCOPE_API_KEY.trim()
  const candidates = [
    path.join(process.cwd(), '.env'),
    path.join(os.homedir(), '.dashscope.env'),
    path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\//, '')), '.env'),
  ]
  for (const f of candidates) {
    try {
      if (!existsSync(f)) continue
      const txt = await readFile(f, 'utf8')
      for (const line of txt.split(/\r?\n/)) {
        const m = line.match(/^\s*(?:DASHSCOPE_API_KEY|ALIYUN_API_KEY|API_KEY)\s*=\s*(.+)\s*$/)
        if (m) return m[1].trim().replace(/^["']|["']$/g, '')
      }
    } catch (e) { /* ignore */ }
  }
  return ''
}

function say(msg) { console.log(msg) }
function elapsed(t0) { return ((Date.now() - t0) / 1000).toFixed(1) + 's' }

function friendlyError(status, body) {
  const code = (body && (body.code || (body.output && body.output.code))) || ''
  const msg = (body && (body.message || (body.output && body.output.message))) || ''
  const hints = [
    ['InvalidApiKey', 'Key 无效或复制时带了空格/引号，检查一下'],
    ['Unauthorized', 'Key 没有权限：确认它属于百炼(DashScope)，且已开通对应模型'],
    ['AccessDenied', '权限不足：这个模型可能没开通，去百炼控制台"模型广场"开通'],
    ['ModelNotFound', '模型名不对，或该账号还没开通这个模型'],
    ['InvalidParameter', '参数不合法：常见是 size/duration 超出该模型范围，或 img_url 不是公网地址'],
    ['Throttling', '限流：并发或配额用完了，等一会儿或申请配额'],
    ['DataInspectionFailed', '内容审核未通过：提示词里可能有敏感内容，换个描述'],
    ['Arrearage', '账户欠费'],
  ]
  for (const pair of hints) {
    if (code.indexOf(pair[0]) >= 0 || msg.indexOf(pair[0]) >= 0) return pair[1]
  }
  return ''
}

async function checkKey(key) {
  say('[1/2] 验证 key ...')
  const res = await fetch(COMPAT, {
    method: 'POST',
    headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'qwen-turbo',
      messages: [{ role: 'user', content: '回复"ok"两个字' }],
      max_tokens: 8,
    }),
  })
  const text = await res.text()
  let body = null
  try { body = JSON.parse(text) } catch (e) { /* 非 JSON */ }
  if (!res.ok) {
    say('    ✗ key 不可用 (HTTP ' + res.status + ')')
    if (body) {
      say('      code: ' + (body.code || body.error?.code || '?'))
      say('      msg : ' + (body.message || body.error?.message || '?'))
    } else {
      say('      ' + text.slice(0, 300))
    }
    const hint = friendlyError(res.status, body)
    if (hint) say('      提示: ' + hint)
    return false
  }
  const content = body?.choices?.[0]?.message?.content || ''
  say('    ✓ key 可用（文本模型返回：' + content.trim().slice(0, 20) + '）')
  return true
}

async function submitVideo(key, args) {
  say('[2/2] 提交视频生成任务 ...')
  say('    模型  : ' + args.model)
  say('    画面  : ' + (args.image ? '图生视频（首帧: ' + args.image.slice(0, 60) + '）' : '文生视频'))
  say('    尺寸  : ' + args.size + '  时长: ' + args.duration + 's')
  say('    提示词: ' + args.prompt.slice(0, 120))

  const input = { prompt: args.prompt }
  if (args.image) input.img_url = args.image
  if (args.inputJson) {
    try {
      Object.assign(input, JSON.parse(args.inputJson))
      say('    已合并 --input 透传参数')
    } catch (e) {
      say('    ✗ --input 不是合法 JSON: ' + e.message)
      return null
    }
  }
  const parameters = { size: args.size, duration: args.duration }
  if (args.paramsJson) {
    try {
      Object.assign(parameters, JSON.parse(args.paramsJson))
      say('    已合并 --params 透传参数')
    } catch (e) {
      say('    ✗ --params 不是合法 JSON: ' + e.message)
      return null
    }
  }
  const payload = { model: args.model, input: input, parameters: parameters }

  if (args.show) {
    say('    --- 将要发送的请求体 ---')
    say(JSON.stringify(payload, null, 2))
    say('    --- 结束（--show 模式不实际提交）---')
    return null
  }

  const res = await fetch(BASE + VIDEO_PATH, {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ' + key,
      'Content-Type': 'application/json',
      'X-DashScope-Async': 'enable',
    },
    body: JSON.stringify(payload),
  })
  const text = await res.text()
  let body = null
  try { body = JSON.parse(text) } catch (e) { /* 非 JSON */ }
  if (!res.ok || !body?.output?.task_id) {
    say('    ✗ 提交失败 (HTTP ' + res.status + ')')
    if (body) {
      say('      code: ' + (body.code || body.output?.code || '?'))
      say('      msg : ' + (body.message || body.output?.message || '?'))
      if (body.request_id) say('      request_id: ' + body.request_id)
    } else {
      say('      ' + text.slice(0, 400))
    }
    const hint = friendlyError(res.status, body)
    if (hint) say('      提示: ' + hint)
    return null
  }
  say('    ✓ 已入队 task_id: ' + body.output.task_id)
  return body.output.task_id
}

async function pollTask(key, taskId, args, t0) {
  const deadline = Date.now() + args.timeoutMin * 60 * 1000
  let last = ''
  while (Date.now() < deadline) {
    await new Promise(function (r) { setTimeout(r, 8000) })
    const res = await fetch(BASE + '/tasks/' + taskId, {
      headers: { 'Authorization': 'Bearer ' + key },
    })
    const body = await res.json().catch(function () { return null })
    const out = body?.output || {}
    const status = out.task_status || '?'
    if (status !== last) {
      say('    [' + elapsed(t0) + '] 状态: ' + status)
      last = status
    }
    if (status === 'SUCCEEDED') {
      const url = out.video_url || out.results?.[0]?.url
      if (!url) { say('    ✗ 成功但没拿到 video_url，完整返回：'); say(JSON.stringify(body).slice(0, 800)); return null }
      return url
    }
    if (status === 'FAILED' || status === 'CANCELED') {
      say('    ✗ 任务失败')
      say('      code: ' + (out.code || '?'))
      say('      msg : ' + (out.message || '?'))
      const hint = friendlyError(200, body)
      if (hint) say('      提示: ' + hint)
      return null
    }
  }
  say('    ✗ 超时（' + args.timeoutMin + ' 分钟）任务仍在 ' + last + '，可稍后用 task_id 继续查：' + taskId)
  return null
}

async function download(url, outDir, t0) {
  await mkdir(outDir, { recursive: true })
  const name = 'video-' + Date.now() + '.mp4'
  const file = path.join(outDir, name)
  say('    下载中 ...')
  const res = await fetch(url)
  if (!res.ok) { say('    ✗ 下载失败 HTTP ' + res.status); return null }
  const buf = Buffer.from(await res.arrayBuffer())
  await writeFile(file, buf)
  say('    ✓ 已保存: ' + file)
  say('    大小: ' + (buf.length / 1024 / 1024).toFixed(2) + ' MB   总耗时: ' + elapsed(t0))
  return file
}

async function diagnose(key) {
  say('服务地址 : ' + BASE)
  say('视频提交 : ' + BASE + VIDEO_PATH)
  say('')
  // 1) 视频接口（免费：查一个不存在的任务，只看 401 还是别的）
  const tasksUrl = BASE + '/tasks/diag-probe'
  try {
    const res = await fetch(tasksUrl, { headers: { Authorization: 'Bearer ' + key } })
    const txt = await res.text()
    let body = null
    try { body = JSON.parse(txt) } catch (e) { /* ignore */ }
    const code = (body && body.code) || ''
    const msg = (body && body.message) || txt
    const authBad = res.status === 401 || res.status === 403 ||
      String(code).includes('InvalidApiKey') || String(code).includes('Unauthorized')
    say((authBad ? '✗' : '✓') + ' 视频接口（任务查询） HTTP ' + res.status)
    say('   ' + code + ' ' + String(msg).slice(0, 200))
    if (authBad) say('   → Key 被这个地址拒绝：Key 与地址不是同一家的')
  } catch (e) {
    say('✗ 视频接口（任务查询） 连不上: ' + e.message)
  }
  say('')
  // 2) 兼容模式文本接口
  try {
    const res = await fetch(COMPAT, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'qwen-turbo', messages: [{ role: 'user', content: '回 ok' }], max_tokens: 4 }),
    })
    const txt = await res.text()
    say((res.status === 200 ? '✓' : '✗') + ' 兼容模式（文本模型） HTTP ' + res.status)
    say('   ' + txt.slice(0, 220))
  } catch (e) {
    say('✗ 兼容模式（文本模型） 连不上: ' + e.message)
  }
  say('')
  say('判断：第一条 ✓ → 这个地址 + Key 能提交视频；两条都 ✗ → 换 Key 或换地址。')
}

async function main() {
  const args = parseArgs(process.argv)
  BASE = normalizeBase(args.base || process.env.DASHSCOPE_BASE_URL || '')
  COMPAT = rootOf(BASE) + '/compatible-mode/v1/chat/completions'
  const key = await loadKey(args.key)
  if (!key) {
    say('✗ 没找到 API Key。三种设置方式（任选一种）：')
    say('  1) 环境变量:  set DASHSCOPE_API_KEY=sk-xxxx      (PowerShell 临时)')
    say('  2) 当前目录 .env 文件，内容一行:  DASHSCOPE_API_KEY=sk-xxxx')
    say('  3) 用户目录 %USERPROFILE%\\.dashscope.env，内容同上')
    process.exit(1)
  }
  say('已载入 key: ' + key.slice(0, 6) + '****' + key.slice(-4) + '（长度 ' + key.length + '）')
  say('服务地址: ' + BASE)

  if (args.diag) {
    await diagnose(key)
    process.exit(0)
  }

  const t0 = Date.now()
  const ok = await checkKey(key)
  if (!ok) process.exit(2)
  if (args.check) { say(''); say('key 验证通过。接下来试视频：'); say('  node verify-dashscope.mjs --prompt "深夜空旷街道，路灯，薄雾，缓慢推镜"'); process.exit(0) }
  if (!args.prompt && !args.show) {
    say('✗ 缺少 --prompt')
    process.exit(1)
  }

  const taskId = await submitVideo(key, args)
  if (!taskId) process.exit(3)
  const url = await pollTask(key, taskId, args, t0)
  if (!url) process.exit(4)
  await download(url, args.outDir, t0)
  say('')
  say('=== 记录这三个数字，用来判断成本 ===')
  say('  耗时: ' + elapsed(t0) + '（含排队）')
  say('  模型: ' + args.model + '  规格: ' + args.size + ' / ' + args.duration + 's')
}

main().catch(function (e) {
  console.error('✗ 未预期的错误: ' + e.message)
  process.exit(9)
})
