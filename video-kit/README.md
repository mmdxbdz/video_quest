# 通义万相视频验证套件

目的：**先花 20 块钱，确认这条路能不能走**，再决定要不要投入做完整 App。

## 一、准备

1. 本机已有 Node 26，不用装东西
2. 把 key 存到文件（**不要发给任何人**）：

```
cd G:\myselfProjects\math_quest\video-kit
"DASHSCOPE_API_KEY=sk-你的完整key" | Out-File -Encoding ascii .env
```

## 二、三步验证

### 第 1 步：只验 key

```
node verify-dashscope.mjs --check
```

- 看到 `✓ key 可用` → key 没问题，进第 2 步
- 看到 `✗ key 不可用` → 对照第四节报错表

### 第 2 步：生成一条 5 秒视频（文生视频）

```
node verify-dashscope.mjs --model wan3.0-video --prompt "深夜空旷的城市街道，路灯昏黄，薄雾，35mm胶片质感，缓慢推镜，电影感"
```

成功后会打印并保存到 `out\video-xxxx.mp4`，同时给出**耗时**。

### 第 3 步：试图生视频（这才是流水线要用的方式）

先用万相文生图出一张首帧图，传到公网可访问的地方（OSS 最方便），然后：

```
node verify-dashscope.mjs --prompt "镜头缓慢推近，人物衣角轻微摆动" --image "https://你的OSS地址/first-frame.jpg" --model wanx2.1-i2v-turbo
```

## 三、模型名

| 用途 | 模型名 |
|---|---|
| **视频（你在用的新版）** | `wan3.0-video` |
| 老版文生视频 | `wanx2.1-t2v-turbo` / `wanx2.1-t2v-plus` |
| 老版图生视频 | `wanx2.1-i2v-turbo` |
| 文生图（做首帧） | `wanx2.1-t2i-turbo` 等 |

脚本默认模型就是 `wan3.0-video`。

### 参数结构对不上怎么办（新模型常见）

新版模型参数名可能和老版不同，用透传直接塞进去：

```
# 合并进 parameters（分辨率、提示词扩写之类）
node verify-dashscope.mjs --model wan3.0-video --prompt "..." --params "{\"resolution\":\"720P\"}"

# 合并进 input（参考图等）
node verify-dashscope.mjs --model wan3.0-video --prompt "..." --input "{\"img_url\":\"https://...\"}"

# 只打印请求体，不提交（先对结构）
node verify-dashscope.mjs --model wan3.0-video --prompt "..." --show
```

**最准的做法**：模型详情页点「API 调用示例」，把它的 `-d` 请求体贴出来（key 涂掉），我照那个结构改。

## 四、报错对照表

| 报错 | 含义 | 怎么办 |
|---|---|---|
| `InvalidApiKey` | key 错或带空格引号 | 重新复制 |
| `Unauthorized` / `AccessDenied` | 这个 key 没权限 | 确认是**百炼**的 key；去控制台开通模型 |
| `ModelNotFound` | 模型名不对 / 未开通 | 换控制台上的准确名字并开通 |
| `InvalidParameter` | size/duration 超范围 | 用 `1280*720`、`720*1280`、5 秒 |
| `Throttling` | 限流/并发满 | 等几分钟或申请配额 |
| `DataInspectionFailed` | 内容审核不通过 | 换提示词（避开真人肖像、暴力、敏感场景） |
| `Arrearage` | 欠费 | 充值 |

## 五、记录这张表（决定项目做不做）

每跑一条填一行：

| 日期 | 模型 | 尺寸/时长 | 耗时 | 一次能用? | 备注 |
|---|---|---|---|---|---|
| | | 5s | | 能 / 不能 | |

**判断标准**（先跑 10 条再看）：

- 一次能用率 **≥ 60%** → 可行，重试成本可控
- **40~60%** → 勉强，必须做挑片界面 + 预算上限
- **< 40%** → 别做全自动，改做「AI 生图 + 强运镜」的降级形态

## 六、下一步

验证通过后，完整流水线：

```
稿子 → LLM 拆分镜 → 每镜首帧图(万相) → 图生视频(万相 i2v, 2~3 候选)
     → 手机挑片 → TTS 配音(Edge TTS 免费) → ffmpeg 拼接+字幕+调色 → MP4
```

需要单独开通：**阿里云智能语音合成**（若不用免费 Edge TTS）。
