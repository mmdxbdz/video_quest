# video_quest —— 写稿出片

输入稿子 → 自动拆成分镜 → 手机直连阿里云通义万相生成电影感视频 → 播放 / 存相册。

**纯手机运行**：不需要电脑、不需要注册会员、不上传稿子、Key 只存在你手机里。

---

## 一、目录结构

```
video_quest/
├── dist/
│   └── app-video.apk          ← 装这个（49 MB）
├── lib/                       ← App 源码
│   ├── main.dart              入口 + 主题
│   ├── models.dart            镜头数据模型、稿子拆句算法
│   ├── dashscope.dart         阿里云 API 客户端（提交 / 轮询 / 下载 / 错误中文化）
│   ├── store.dart             设置与任务持久化（Key 存 Android Keystore）
│   ├── runner.dart            全局生成器：进度/阶段/取消（离开页面也在跑）
│   ├── native.dart            原生能力桥（全屏播放）
│   └── screens/               首页 / 设置 / 写稿 / 生成队列
├── android/                  ← 原生工程（含自写的 PlayerActivity 播放器）
├── test/                     ← 单元测试（拆句逻辑）
├── video-kit/                ← 命令行验证工具（不用装 APK 就能测 API）
│   ├── verify-dashscope.mjs   一键验证 Key / 模型 / 出片耗时
│   └── README.md
├── build-apk.ps1             ← 一键构建脚本
└── README.md
```

## 二、装到手机

1. 把 `dist\app-video.apk` 传到手机安装（允许"安装未知来源应用"）
2. 首次打开 → 右上角齿轮 → 填 **API Key**（阿里云百炼的 `sk-...`）→ 保存
3. 回首页 → 「写稿出片」→ 粘稿子 → 「拆成镜头」→ 「开始生成」

> Key 存在手机系统加密存储（Android Keystore），**不在安装包内**，也不会上传任何服务器。

## 三、用法要点

| 步骤 | 说明 |
|---|---|
| 粘稿子 | 按「。」「！」「？」或换行自动切成镜头，每镜约 10~26 字 |
| 改文案 | 每段可单独编辑（想让某镜更电影感，就自己加描述） |
| 生成 | 逐条提交，**实时显示阶段**（提交中 → 已入队 → 模型生成中 → 下载中）、当前是第几个镜头、走了多少秒，失败可单条重试（省钱） |
| 看进度 | 生成时返回首页，顶部会留一条「正在生成 · 3/8 · 模型生成中 · 01:24」横幅，点它回到详情；同时只能跑一个任务，防止重复扣费 |
| 停止 | 生成中点「停止（当前镜头跑完就停）」 |
| 出片 | 「播放」（全屏循环）/「存相册」（存到相册相簿「AI成片」）|

## 四、设置项

| 设置 | 默认 | 说明 |
|---|---|---|
| API Key | 空 | 阿里云百炼 Key，只存本机 |
| **服务地址** | `https://dashscope.aliyuncs.com/api/v1` | **Key 和地址必须同一家**。用百炼通用 Key 就保持默认；用专有/独享网关（如 `xxx.maas.aliyuncs.com`）的 Key 就填该网关，粘 `/compatible-mode/v1` 结尾的地址也行，会自动换成 `/api/v1` |
| 测试连接 | — | 不花钱的连通性自检：查一次任务 + 发一条极短文本请求，直接告诉你 Key 和地址配没配对 |
| 视频模型 | `wan3.0-video` | 与控制台一致 |
| 画面尺寸 | `720*1280` | 竖屏；横屏改 `1280*720` |
| 镜头时长 | 5 秒 | 5/6/8/10 |
| 风格后缀 | 35mm胶片质感… | 拼到每个镜头提示词后面，统一电影感 |
| 每次最多镜头 | 4 | **省钱保险丝**，建议第一次设 1 |
| 高级参数 | 空 | 模型报 `InvalidParameter` 时，按官方示例填 JSON 透传 |

## 五、费用

每个镜头 = 一次生成调用 = 一次计费。4 镜头的片子 = 4 次调用。
**第一次务必把「每次最多镜头数」设成 1**，确认单价和效果再放开。

## 六、重新构建

```
cd G:\myselfProjects\video_quest
.\build-apk.ps1            # 增量构建
.\build-apk.ps1 -Clean      # 干净重建
```

脚本会自动：设 JDK / Android SDK / **国内镜像** → `flutter build apk --release` → 复制成 `dist\app-video.apk`。

### 构建坑（改配置前必看）

| 现象 | 原因 | 处理 |
|---|---|---|
| Gradle 卡几十分钟没动静 | 引擎 JNI 包从 Google 源拉不动 | 必须设 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（脚本已设） |
| Gradle 下载 504 | gradle-9.3.1 从 GitHub 取不到 | wrapper 已指向腾讯镜像 |
| Kotlin 增量缓存报错 | 强杀构建留下的脏缓存 | 已设 `kotlin.incremental=false` |
| `Gradle build failed to produce an .apk file` | 手动删了 APK，Gradle 判定任务最新 | 别手删产物，用 `-Clean` 重建 |
| Maven 依赖拉得慢 | google()/mavenCentral() 国内慢 | 已加阿里云 Maven 镜像 |

## 七、不用 APK 也能测 API

`video-kit\verify-dashscope.mjs` 是一个 Node 脚本，用来验证 Key、模型是否可用、单条出片耗时：

```
cd G:\myselfProjects\video_quest\video-kit
"DASHSCOPE_API_KEY=sk-你的key" | Out-File -Encoding ascii .env
node verify-dashscope.mjs --check
node verify-dashscope.mjs --model wan3.0-video --prompt "深夜空旷街道，薄雾，缓慢推镜，电影感"
```

**先查 Key 和地址配没配对（不花钱，最常用）**：

```
# 百炼通用 Key
node verify-dashscope.mjs --key "sk-你的key" --diag

# 专有网关 Key（地址随便怎么粘，脚本会自动规整成 /api/v1）
node verify-dashscope.mjs --key "sk-你的key" --base "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1" --diag
```

输出两条：`视频接口（任务查询）` 和 `兼容模式（文本模型）`，各自 ✓/✗ 加 HTTP 状态码——
视频那条 ✓ 才说明这个地址 + Key 能提交视频任务。

细节见 `video-kit\README.md`。

## 八、当前版本限制

- **不拼接多镜头**（手机端没有 FFmpeg）：导出的是独立镜头，用剪映拼成完整片
- 播放器是自写的极简全屏播放，不能导出
- 画面提示词 = 原句 + 风格后缀，暂不接大模型润色（V2 计划）

## 九、常用报错

| App 里显示 | 原因 | 处理 |
|---|---|---|
| `InvalidApiKey` | Key 粘错（带空格/引号）**或 Key 与「服务地址」不是同一家** | 重新粘贴；再点「测试连接」看是哪一条不通 |
| `AccessDenied` / `Unauthorized` | Key 无该模型权限 | 百炼控制台开通模型 |
| `ModelNotFound` | 模型名不对 | 改设置里的模型名 |
| `InvalidParameter` | 参数结构与模型不匹配 | 用「高级参数」透传，或对照官方 curl 示例 |
| `DataInspectionFailed` | 内容审核未过 | 换个说法 |
| `Throttling` | 限流 | 等几分钟 |
| `HTTP404` / `No match` | 地址填成了 `/compatible-mode/v1`（那是文本协议） | 视频接口是「域名 + `/api/v1`」 |

### Key 明明有效，App 却说无效？

阿里云有两类 API Key，认的域名不一样，**配错就是永远 InvalidApiKey**：

| Key 来自 | 服务地址 | 说明 |
|---|---|---|
| 百炼（DashScope 通用） | `https://dashscope.aliyuncs.com/api/v1` | 默认值，视频模型最全 |
| 百炼独享实例 / PAI-MaaS 网关 | `https://你的网关域名/api/v1` | 例如 `token-plan.cn-beijing.maas.aliyuncs.com`，视频能力取决于该网关开通了哪些模型 |

另外 `/compatible-mode/v1` 是 **OpenAI 兼容协议**，只覆盖文本/向量这类同步接口；视频生成走的是 DashScope 原生异步协议：

```
POST {域名}/api/v1/services/aigc/video-generation/video-synthesis   （带 X-DashScope-Async: enable）
GET  {域名}/api/v1/tasks/{task_id}
```

所以地址里带 `compatible-mode` 的部分必须去掉（App 里会自动去掉）。
