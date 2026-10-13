# -*- coding: utf-8 -*-
"""
抖音短视频批量生产脚本
====================
输入：topics.json（题库）
输出：output/{id}_{answer}.mp4（15 秒竖版短视频）

时间节点（15 秒）：
  0-2s   hook 悬念 + hook 配音
  2-5s   question + 3/2/1 倒计时 + question 配音
  5-10s  answer 大字揭晓 + answer 配音
  10-13s explain 解释 + explain 配音
  13-15s 关注引导 + 静音

依赖：pip install edge-tts Pillow
      系统需装 ffmpeg 并加 PATH
"""

import json
import os
import sys
import subprocess
import asyncio
import random
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# ============ 配置 ============
BASE_DIR = Path(__file__).parent.resolve()
TOPICS_FILE = BASE_DIR / "topics.json"
CACHE_DIR = BASE_DIR / "cache"
OUTPUT_DIR = BASE_DIR / "output"
CACHE_AUDIO = CACHE_DIR / "audio"
CACHE_FRAMES = CACHE_DIR / "frames"

W, H = 1080, 1920          # 竖版分辨率
FPS = 30
DURATION = 15              # 总时长 15 秒
VOICE = "zh-CN-XiaoxiaoNeural"  # edge-tts 中文语音

# 时间节点（秒）
T_HOOK_START = 0
T_HOOK_END = 2
T_Q_START = 2
T_Q_END = 5
T_A_START = 5
T_A_END = 10
T_E_START = 10
T_E_END = 13
T_END_START = 13
T_END_END = 15

# 颜色主题（冷色渐变）
BG_COLORS = [
    (30, 144, 255),   # 道奇蓝
    (148, 103, 189),  # 紫
    (255, 140, 0),    # 橙
    (50, 205, 50),    # 绿
    (220, 20, 60),    # 猩红
]
TEXT_COLOR = (255, 255, 255)
ACCENT_COLOR = (255, 255, 0)   # 黄色强调

# 中文字体（Windows 默认路径）
FONT_PATH_CANDIDATES = [
    r"C:\Windows\Fonts\msyhbd.ttc",      # 微软雅黑粗体
    r"C:\Windows\Fonts\msyh.ttc",        # 微软雅黑
    r"C:\Windows\Fonts\simhei.ttf",      # 黑体
    r"C:\Windows\Fonts\simsun.ttc",      # 宋体
    "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",   # Linux
    "/System/Library/Fonts/PingFang.ttc",               # macOS
]


# ============ 工具函数 ============

def get_font(size: int) -> ImageFont.FreeTypeFont:
    """获取中文字体，找不到就用默认"""
    for p in FONT_PATH_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    # 兜底：用系统任意 TTF
    import subprocess
    result = subprocess.run(
        ["fc-list", ":lang=zh", "file"],
        capture_output=True, text=True
    )
    if result.stdout.strip():
        path = result.stdout.strip().split("\n")[0].split(":")[0]
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


def get_bg_color(seed: str) -> tuple:
    """根据 id 选背景色"""
    random.seed(seed)
    return random.choice(BG_COLORS)


def wrap_text(draw, text: str, font, max_width: int) -> list:
    """文字自动换行"""
    lines = []
    current = ""
    for ch in text:
        test = current + ch
        bbox = draw.textbbox((0, 0), test, font=font)
        if bbox[2] - bbox[0] > max_width:
            if current:
                lines.append(current)
            current = ch
        else:
            current = test
    if current:
        lines.append(current)
    return lines


def draw_text_centered(draw, text: str, y: int, font, color, max_width=None):
    """居中画文字，支持换行"""
    if max_width is None:
        max_width = W - 120
    lines = wrap_text(draw, text, font, max_width)
    line_h = draw.textbbox((0, 0), "测", font=font)[3] + 10
    total_h = len(lines) * line_h
    start_y = y - total_h // 2
    for i, line in enumerate(lines):
        bbox = draw.textbbox((0, 0), line, font=font)
        lw = bbox[2] - bbox[0]
        draw.text(((W - lw) // 2, start_y + i * line_h), line,
                  fill=color, font=font)


def add_ai_watermark(img: Image.Image) -> Image.Image:
    """左上角加 'AI 生成' 水印（2026 强制要求）"""
    draw = ImageDraw.Draw(img)
    font = get_font(36)
    tag_text = "AI 生成"
    bbox = draw.textbbox((0, 0), tag_text, font=font)
    tag_w, tag_h = bbox[2] - bbox[0] + 24, bbox[3] - bbox[1] + 16
    # 圆角背景
    draw.rounded_rectangle((20, 20, 20 + tag_w, 20 + tag_h),
                           radius=8, fill=(0, 0, 0, 160))
    draw.text((36, 28), tag_text, fill=(255, 255, 255), font=font)
    return img


# ============ 帧生成 ============

def make_frame(
    bg_color,
    hook=None, question=None, emoji=None, wrong_guess=None,
    answer=None, explain=None, countdown=None, is_end=False
) -> Image.Image:
    """生成 1080x1920 竖版关键帧"""
    img = Image.new("RGB", (W, H), bg_color)
    draw = ImageDraw.Draw(img)

    # 装饰：底部渐变色带
    for i in range(200):
        alpha = int(255 * (i / 200))
        draw.line([(0, H - 200 + i), (W, H - 200 + i)],
                  fill=(255, 255, 255, alpha // 4))

    # 装饰：右上角小圆圈
    draw.ellipse([W - 200, 100, W - 50, 250],
                 outline=(255, 255, 255, 80), width=3)
    draw.ellipse([W - 180, 120, W - 70, 230],
                 outline=(255, 255, 255, 60), width=2)

    if is_end:
        # 结尾：关注引导
        big_font = get_font(120)
        small_font = get_font(50)
        draw_text_centered(draw, "关注我", H // 2 - 100, big_font, TEXT_COLOR)
        draw_text_centered(draw, "明天继续涨知识", H // 2 + 50, small_font, ACCENT_COLOR)
        # 头像占位圆
        draw.ellipse([W // 2 - 120, H // 2 - 380, W // 2 + 120, H // 2 - 140],
                     fill=(255, 255, 255, 60), outline=TEXT_COLOR, width=4)
        draw_text_centered(draw, "头像", H // 2 - 260, get_font(60), TEXT_COLOR)

    elif countdown is not None:
        # 倒计时帧：中间大字 3、2、1
        big_font = get_font(300)
        draw_text_centered(draw, str(countdown), H // 2, big_font, ACCENT_COLOR)
        # 同时显示题目
        if question:
            draw_text_centered(draw, question, H // 2 - 500, get_font(56), TEXT_COLOR)

    elif answer is not None and explain is not None:
        # 答案揭晓帧
        # emoji/题目
        if emoji:
            big_font = get_font(180)
            draw_text_centered(draw, emoji, H // 2 - 550, big_font, TEXT_COLOR)
        # 答案大字
        ans_font = get_font(140)
        draw_text_centered(draw, answer, H // 2 - 200, ans_font, ACCENT_COLOR)
        # 解释
        exp_font = get_font(48)
        draw_text_centered(draw, explain, H // 2 + 200, exp_font, TEXT_COLOR)
        # 错误猜测提示（谐音梗）
        if wrong_guess:
            wrong_font = get_font(36)
            draw_text_centered(draw, f"你猜了：{wrong_guess}？不对哦",
                               H // 2 + 500, wrong_font, (200, 200, 200))

    elif hook is not None:
        # Hook 悬念帧
        big_font = get_font(110)
        draw_text_centered(draw, hook, H // 2, big_font, ACCENT_COLOR)
        # 小字提示
        draw_text_centered(draw, "看完你就懂了", H // 2 + 300, get_font(40), (220, 220, 220))

    img = add_ai_watermark(img)
    return img


def generate_all_frames(topic: dict, bg_color: tuple) -> dict:
    """生成一条题目的全部关键帧，返回帧路径字典"""
    tid = topic["id"]
    frames_dir = CACHE_FRAMES / tid
    frames_dir.mkdir(parents=True, exist_ok=True)

    frame_paths = {}

    # Frame 0: hook
    img = make_frame(bg_color, hook=topic.get("hook", ""))
    p = frames_dir / "f0_hook.png"
    img.save(p); frame_paths["hook"] = str(p)

    # Frame 1-3: 倒计时 3, 2, 1
    question = topic.get("question") or topic.get("emoji", "")
    for i, n in enumerate([3, 2, 1]):
        img = make_frame(bg_color, question=question, countdown=n)
        p = frames_dir / f"f{i+1}_countdown_{n}.png"
        img.save(p)
    frame_paths["countdown_start"] = str(frames_dir / "f1_countdown_3.png")

    # Frame 4: question 常显（给时长用）
    img = make_frame(bg_color, question=question, countdown=0)
    p = frames_dir / "f4_question.png"
    img.save(p)
    frame_paths["question"] = str(p)

    # Frame 5: answer + explain
    img = make_frame(bg_color,
                     emoji=topic.get("emoji"),
                     wrong_guess=topic.get("wrong_guess"),
                     answer=topic["answer"],
                     explain=topic["explain"])
    p = frames_dir / "f5_answer.png"
    img.save(p); frame_paths["answer"] = str(p)

    # Frame 6: end
    img = make_frame(bg_color, is_end=True)
    p = frames_dir / "f6_end.png"
    img.save(p); frame_paths["end"] = str(p)

    return frame_paths


# ============ TTS ============

async def gen_tts(text: str, output_path: str) -> None:
    """edge-tts 生成 MP3"""
    import edge_tts
    communicate = edge_tts.Communicate(text, VOICE)
    await communicate.save(output_path)


async def gen_all_tts(topic: dict) -> dict:
    """生成一条题目的 4 段配音，返回路径字典"""
    tid = topic["id"]
    audio_dir = CACHE_AUDIO / tid
    audio_dir.mkdir(parents=True, exist_ok=True)

    segments = {
        "hook": topic.get("hook", ""),
        "question": topic.get("question") or topic.get("emoji", ""),
        "answer": topic["answer"],
        "explain": topic["explain"],
    }

    paths = {}
    for key, text in segments.items():
        if not text:
            continue
        out = audio_dir / f"{key}.mp3"
        if not out.exists():
            await gen_tts(text, str(out))
        paths[key] = str(out)

    return paths


def get_audio_duration(path: str) -> float:
    """用 ffprobe 获取音频时长（秒）"""
    result = subprocess.run(
        ["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True
    )
    try:
        return float(result.stdout.strip())
    except Exception:
        return 1.0


# ============ ffmpeg 合成 ============

def synthesize_video(topic: dict, frame_paths: dict, audio_paths: dict) -> str:
    """
    用 ffmpeg 按时间线合成视频。
    策略：先生成 5 段独立片段，再 concat 拼起来。
    """
    tid = topic["id"]
    safe_answer = topic["answer"].replace("/", "_")
    out_path = OUTPUT_DIR / f"{tid}_{safe_answer}.mp4"
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # 各段时长
    d_hook = T_HOOK_END - T_HOOK_START     # 2s
    d_q = T_Q_END - T_Q_START              # 3s
    d_a = T_A_END - T_A_START              # 5s
    d_e = T_E_END - T_E_START              # 3s
    d_end = T_END_END - T_END_START        # 2s

    # 用 ffmpeg 逐段生成 + concat
    work_dir = CACHE_DIR / "ffmpeg_work"
    work_dir.mkdir(parents=True, exist_ok=True)

    segments = []

    # Segment 1: hook (2s, frame + audio)
    s1 = work_dir / f"{tid}_s1.mp4"
    a_hook = audio_paths.get("hook")
    if a_hook:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_hook), "-i", frame_paths["hook"],
            "-i", a_hook,
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s1)
        ], capture_output=True, check=True)
    else:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_hook), "-i", frame_paths["hook"],
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s1)
        ], capture_output=True, check=True)
    segments.append(s1)

    # Segment 2: question 倒计时 (3s, 3 张图各 1s)
    # 简化：用 question 常显帧 + question 配音
    s2 = work_dir / f"{tid}_s2.mp4"
    a_q = audio_paths.get("question")
    if a_q:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_q), "-i", frame_paths["question"],
            "-i", a_q,
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s2)
        ], capture_output=True, check=True)
    else:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_q), "-i", frame_paths["question"],
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s2)
        ], capture_output=True, check=True)
    segments.append(s2)

    # Segment 3: answer (5s)
    s3 = work_dir / f"{tid}_s3.mp4"
    a_a = audio_paths.get("answer")
    if a_a:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_a), "-i", frame_paths["answer"],
            "-i", a_a,
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s3)
        ], capture_output=True, check=True)
    else:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_a), "-i", frame_paths["answer"],
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s3)
        ], capture_output=True, check=True)
    segments.append(s3)

    # Segment 4: explain (3s) — 同 answer 帧
    s4 = work_dir / f"{tid}_s4.mp4"
    a_e = audio_paths.get("explain")
    if a_e:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_e), "-i", frame_paths["answer"],
            "-i", a_e,
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s4)
        ], capture_output=True, check=True)
    else:
        subprocess.run([
            "ffmpeg", "-y",
            "-loop", "1", "-t", str(d_e), "-i", frame_paths["answer"],
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest",
            "-vf", f"scale={W}:{H}",
            str(s4)
        ], capture_output=True, check=True)
    segments.append(s4)

    # Segment 5: end (2s, 无声)
    s5 = work_dir / f"{tid}_s5.mp4"
    subprocess.run([
        "ffmpeg", "-y",
        "-loop", "1", "-t", str(d_end), "-i", frame_paths["end"],
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest",
        "-vf", f"scale={W}:{H}",
        str(s5)
    ], capture_output=True, check=True)
    segments.append(s5)

    # concat 所有段
    list_file = work_dir / f"{tid}_list.txt"
    with open(list_file, "w", encoding="utf-8") as f:
        for s in segments:
            f.write(f"file '{s.as_posix()}'\n")

    subprocess.run([
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0", "-i", str(list_file),
        "-c", "copy",
        str(out_path)
    ], capture_output=True, check=True)

    return str(out_path)


# ============ 主流程 ============

def load_topics(limit: int = None) -> list:
    with open(TOPICS_FILE, "r", encoding="utf-8") as f:
        topics = json.load(f)
    if limit:
        topics = topics[:limit]
    return topics


async def process_one(topic: dict) -> str:
    """处理一条题目：帧 + 配音 + 合成"""
    tid = topic["id"]
    print(f"[{tid}] 开始处理：{topic['answer']}")

    bg_color = get_bg_color(tid)
    frame_paths = generate_all_frames(topic, bg_color)

    try:
        audio_paths = await gen_all_tts(topic)
    except Exception as e:
        print(f"  [{tid}] edge-tts 失败，跳过配音：{e}")
        audio_paths = {}

    try:
        out = synthesize_video(topic, frame_paths, audio_paths)
        print(f"  [{tid}] 完成 → {out}")
        return out
    except Exception as e:
        print(f"  [{tid}] 合成失败：{e}")
        return ""


async def main(limit: int = None):
    # 前置检查
    if not TOPICS_FILE.exists():
        print(f"找不到 {TOPICS_FILE}")
        sys.exit(1)

    ffmpeg_check = subprocess.run(
        ["ffmpeg", "-version"], capture_output=True
    )
    if ffmpeg_check.returncode != 0:
        print("找不到 ffmpeg，请安装并加 PATH")
        sys.exit(1)

    OUTPUT_DIR.mkdir(exist_ok=True)
    CACHE_AUDIO.mkdir(parents=True, exist_ok=True)
    CACHE_FRAMES.mkdir(parents=True, exist_ok=True)

    topics = load_topics(limit)
    print(f"共 {len(topics)} 条题目，开始批量生成...\n")

    results = []
    for topic in topics:
        try:
            path = await process_one(topic)
            results.append(path)
        except Exception as e:
            print(f"  [{topic['id']}] 异常：{e}")

    print(f"\n完成！成功 {sum(1 for r in results if r)} / {len(topics)}")
    for r in results:
        if r:
            print(f"  → {r}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="抖音短视频批量生成")
    parser.add_argument("--count", type=int, default=None,
                        help="只生成前 N 条（测试用）")
    args = parser.parse_args()

    asyncio.run(main(limit=args.count))
