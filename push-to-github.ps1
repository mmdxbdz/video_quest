# 把 video_quest 推到 https://github.com/mmdxbdz/video_quest
# 用法（任选一种）：
#   右键「使用 PowerShell 运行」，或：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\push-to-github.ps1
# 首次推送会由 Git Credential Manager 弹浏览器授权（你已在浏览器登录 GitHub，点 Authorize 即可）
param(
    [string]$Remote = "https://github.com/mmdxbdz/video_quest.git",
    [string]$Branch = "main"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "没找到 git，先装 Git for Windows：https://git-scm.com/download/win" -ForegroundColor Red
    exit 1
}

# 0) 兜底：绝不把安装包/构建产物/密钥提交上去
$gi = Get-Content .gitignore -Raw -ErrorAction SilentlyContinue
if ($gi -notmatch '(?m)^/dist/') {
    Add-Content .gitignore "`n# 构建产物 / 安装包（不进仓库）`n/dist/`n*.apk`n*.aab`n/video-kit/out/`n.env`n*.jks`n*.keystore`n/android/.kotlin/`n"
}

# 1) 初始化（已有仓库就跳过）
if (-not (Test-Path .git)) {
    Step "git init"
    git init -b $Branch | Out-Null
} else {
    Step "已是 git 仓库，跳过 init"
}

# 2) 暂存 + 提交
Step "暂存文件"
git add -A
$staged = (git diff --cached --name-only | Measure-Object -Line).Lines
if ($staged -eq 0) {
    Step "没有新改动，跳过提交"
} else {
    Write-Host "    将提交 $staged 个文件" -ForegroundColor DarkGray
    git commit -m "feat: 可配置 API 服务地址 + 连接自检（支持专有网关 Key）"
}

# 3) 远端
$existing = git remote 2>$null
if ($existing -notcontains "origin") {
    Step "添加远端 origin"
    git remote add origin $Remote
} else {
    # 已有 origin（可能是 SSH 形式）就别乱改，尊重仓库现有配置
    $current = (git remote get-url origin) 2>$null
    Step "远端已存在，保持不动：$current"
}

# 4) 推送（这里会弹浏览器授权）
Step "推送到 $Remote ($Branch)"
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "推送失败？常见两种：" -ForegroundColor Yellow
    Write-Host "  A. 远端已有提交（非空仓库）→ 执行： git pull --rebase origin $Branch  再 git push -u origin $Branch"
    Write-Host "  B. 授权窗口没弹 / 拒绝 → 用 PAT："
    Write-Host '     git remote set-url origin https://<你的PAT>@github.com/mmdxbdz/video_quest.git'
    Write-Host '     git push -u origin ' + $Branch
    Write-Host '     推完把地址改回干净形式： git remote set-url origin ' + $Remote
    exit 1
}

Write-Host ""
Write-Host "完成：https://github.com/mmdxbdz/video_quest" -ForegroundColor Green
git --no-pager log --oneline -3
git --no-pager show --stat --oneline HEAD | Select-Object -First 5
