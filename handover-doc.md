# 短视频批量生产项目交接文档

## 项目目标

抖音账号"梗王答题本"批量生产 15 秒竖版短视频，日更 1-2 条，内容类型：谐音梗 / 脑筋急转弯 / 冷知识。

## 技术栈（全部免费，无需 API Key）

| 环节 | 工具 | 说明 |
|------|------|------|
| AI 配音 | edge-tts | 微软免费 TTS，支持中文，无需 Key |
| 配图 | Pillow (PIL) | 代码生成纯色背景 + emoji/文字，无需外部图 |
| 字幕烧录 | ffmpeg | 系统级视频处理 |
| 视频合成 | ffmpeg | 图片 + 音频 + 字幕 → mp4 |

## 工作环境

- 操作系统：Windows
- 工作目录：`D:\Desktop\短视频\`
- Python 版本：3.10+

## 目录结构

```
D:\Desktop\短视频\
├── topics.json              # 题库（输入）
├── generate.py              # 主脚本
├── assets\
│   └── fonts\
│       └── bold.ttf         # 中文字体（必须有！）
├── cache\                   # 中间产物（自动创建）
└── output\                  # 成品 MP4（自动创建）
```

## 安装依赖（Windows CMD）

```cmd
pip install edge-tts Pillow
```

同时确保已安装 ffmpeg，加 PATH。命令行输入 `ffmpeg -version` 有输出即可。

## 中文字体

Pillow 渲染中文必须有支持中文的 TTF 字体。Windows 自带：
- `C:\Windows\Fonts\msyhbd.ttc`（微软雅黑粗体）
- `C:\Windows\Fonts\simhei.ttf`（黑体）

脚本默认用 `C:\Windows\Fonts\msyhbd.ttc`，如果不存在，把字体文件拷到 `assets\fonts\` 下，改脚本里的 FONT_PATH 即可。

## 视频规格

| 项 | 值 |
|----|-----|
| 分辨率 | 1080x1920（竖版）|
| 时长 | 15 秒 |
| 帧率 | 30 fps |
| 字幕 | 烧录到画面 |
| AI 生成标注 | 画面左上角 |

## 一条视频的 5 个时间节点（15 秒）

| 时段 | 画面 | 音频 | 字幕 |
|------|------|------|------|
| 0-2s | hook 悬念文字 | AI 配音念 hook | hook 大字 |
| 2-5s | question + 倒计时 3、2、1 | 倒计时滴答 | question |
| 5-10s | answer 大字揭晓 + 配图 | AI 配音念 answer | answer 大字 |
| 10-13s | explain 解释 | AI 配音念 explain | explain |
| 13-15s | 黑底"关注我" + 头像 | 静音/背景音 | 关注引导 |

## topics.json 格式

```json
[
  {
    "id": "001",
    "type": "谐音梗",
    "emoji": "🐔📈",
    "wrong_guess": "鸡飞",
    "answer": "鸡犬升天",
    "explain": "一人得道，鸡犬都跟着升天",
    "hook": "你以为这只是鸡飞？"
  },
  {
    "id": "002",
    "type": "脑筋急转弯",
    "question": "什么东西越洗越脏？",
    "answer": "水",
    "explain": "水越洗越脏，因为脏东西都进了水里",
    "hook": "这题 99% 的人答错"
  },
  {
    "id": "003",
    "type": "冷知识",
    "question": "章鱼有几颗心脏？",
    "answer": "3 颗",
    "explain": "2 颗供血鳃，1 颗供全身",
    "hook": "章鱼其实是外星生物？"
  }
]
```

字段说明：
- `type` 决定画面风格（谐音梗显示 emoji，其余显示 question）
- `hook` 是片头钩子，制造好奇
- `explain` 控制在 20 字内，配音时长 3 秒

## 运行方式

```cmd
cd D:\Desktop\短视频
python generate.py              # 用 topics.json 全部题目批量生成
python generate.py --count 3    # 只生成前 3 条（测试用）
```

## 脚本功能（generate.py）

1. 读取 topics.json
2. 对每条题目：
   a. edge-tts 生成 hook / question / answer / explain 四段配音 → cache/audio/{id}_*.mp3
   b. Pillow 按时间节点生成 5 张关键帧 → cache/frames/{id}_*.png
   c. ffmpeg 合成：按时间线拼接帧 + 音频 + 烧录字幕 → output/{id}_{answer}.mp4
3. 画面左上角加"AI 生成"水印
4. 清理 cache（可选）

## 验证流程

1. 先跑 1 条：`python generate.py --count 1`
2. 检查 output 下是否有 mp4
3. 打开看：画面清晰？字幕可读？配音正常？时间节点对？
4. 没问题后去掉 --count 批量跑

## 常见问题

| 问题 | 解决 |
|------|------|
| Pillow 中文乱码 | 检查 FONT_PATH 是否指向支持中文的 TTF |
| edge-tts 超时 | 换网络或重试，微软服务器偶尔抽风 |
| ffmpeg 找不到 | 装完加 PATH，或把 ffmpeg.exe 放脚本同目录 |
| 配音时长对不上 | adjust_timing() 函数已自动对齐 ±0.5s 内 |

## 后续可扩展

1. 接入即梦 API 生成真实配图（替换 Pillow 纯色图）
2. 接入抖音同款音色（火山引擎 TTS，需 Key）
3. 自动上传抖音（需开放平台上传权限）
4. 定时任务：每周日晚自动批量生成下周 7 条
