#!/usr/bin/env bash
# 将单个视频压缩为 MP4，保留原分辨率和帧率。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$ROOT/compressed"
CODEC=hevc
CRF=24
AUTO=0
NO_AUDIO=0
CRF_SPECIFIED=0
MIN_SSIM=0.995
INPUT=""

usage() {
  cat <<'EOF'
用法: ./compress-video.sh <视频文件> [--codec hevc|h264] [--crf 14-30] [--no-audio] [--auto] [--min-ssim 0.995]

视频文件可写 source/ 下的文件名，也可写完整或相对路径。
默认 H.265/HEVC、CRF 24；--crf 22 可获得更保画质的成品。
--auto 才会自动试压 CRF 14-30，选择全片 SSIM 达标且比原片小的成品。
自动试压的默认 SSIM 门槛为 0.995；它不能保证肉眼完全无差异。
CRF 越小画质越高、文件通常越大。
成品在 compressed/，已存在的文件不会被覆盖。
--no-audio 会移除音轨，输出文件名添加 _no_audio。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codec)
      if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi
      CODEC="$2"
      shift 2
      ;;
    --crf)
      if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi
      CRF="$2"
      CRF_SPECIFIED=1
      shift 2
      ;;
    --auto)
      AUTO=1
      shift
      ;;
    --no-audio)
      NO_AUDIO=1
      shift
      ;;
    --min-ssim)
      if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi
      MIN_SSIM="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "未知选项: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$INPUT" ]]; then
        echo "每次只接受一个视频文件" >&2
        exit 1
      fi
      INPUT="$1"
      shift
      ;;
  esac
done

if [[ -z "$INPUT" || ( "$CODEC" != hevc && "$CODEC" != h264 ) ]]; then
  usage >&2
  exit 1
fi
if [[ ! "$CRF" =~ ^(1[4-9]|2[0-9]|30)$ || ( "$AUTO" -eq 1 && "$CRF_SPECIFIED" -eq 1 ) ]]; then
  usage >&2
  exit 1
fi
if [[ ! "$MIN_SSIM" =~ ^0\.[0-9]+$ ]] || ! awk -v x="$MIN_SSIM" 'BEGIN { exit !(x > 0 && x < 1) }'; then
  usage >&2
  exit 1
fi

if [[ -f "$ROOT/source/$INPUT" ]]; then
  INPUT="$ROOT/source/$INPUT"
elif [[ ! -f "$INPUT" ]]; then
  echo "文件不存在: $INPUT" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "未找到 ffmpeg，请先安装 FFmpeg" >&2
  exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "未找到 ffprobe，请先安装 FFmpeg" >&2
  exit 1
fi

name="$(basename "$INPUT")"
mkdir -p "$OUTPUT_DIR"
echo "输入: $INPUT"
echo "编码: $CODEC"

audio_args=(-an)
if [[ "$NO_AUDIO" -eq 0 && -n "$(ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$INPUT")" ]]; then
  audio_args=(-c:a aac -b:a 128k)
fi

output_suffix=""
if [[ "$NO_AUDIO" -eq 1 ]]; then output_suffix="_no_audio"; fi

encode() {
  local quality="$1" target="$2"
  local video_args=(-c:v libx265 -preset slow -crf "$quality" -pix_fmt yuv420p -tag:v hvc1 -x265-params log-level=error)
  if [[ "$CODEC" == h264 ]]; then
    video_args=(-c:v libx264 -preset slow -crf "$quality" -pix_fmt yuv420p)
  fi
  ffmpeg -hide_banner -loglevel error -i "$INPUT" \
    -map 0:v:0 -map 0:a? -sn -dn \
    "${video_args[@]}" "${audio_args[@]}" \
    -movflags +faststart -y "$target"
}

if [[ "$AUTO" -eq 0 ]]; then
  output="$OUTPUT_DIR/${name%.*}_${CODEC}_crf${CRF}${output_suffix}.mp4"
  if [[ -e "$output" ]]; then echo "输出已存在: $output" >&2; exit 1; fi
  encode "$CRF" "$output"
  echo "完成: $output"
  exit 0
fi

echo "自动试压: 全片 SSIM ≥ ${MIN_SSIM}，且文件小于原片"
source_bytes="$(stat -f %z "$INPUT")"
tmpdir="$(mktemp -d "$OUTPUT_DIR/.compress.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
low=14
high=30
best_crf=""
best_bytes="$source_bytes"
best_score=""

while (( low <= high )); do
  trial=$(( (low + high) / 2 ))
  candidate="$tmpdir/crf${trial}.mp4"
  encode "$trial" "$candidate"
  score_log="$(ffmpeg -hide_banner -nostats -loglevel info -i "$INPUT" -i "$candidate" \
    -filter_complex '[0:v:0][1:v:0]ssim' -an -f null - 2>&1)"
  if [[ ! "$score_log" =~ All:([0-9]+\.[0-9]+) ]]; then
    echo "无法读取 SSIM 结果" >&2
    exit 1
  fi
  score="${BASH_REMATCH[1]}"
  bytes="$(stat -f %z "$candidate")"
  echo "CRF $trial: SSIM $score, $bytes bytes"

  if awk -v score="$score" -v target="$MIN_SSIM" 'BEGIN { exit !(score >= target) }'; then
    if (( bytes < best_bytes )); then
      best_crf="$trial"
      best_bytes="$bytes"
      best_score="$score"
    fi
    low=$((trial + 1))
  else
    high=$((trial - 1))
  fi
done

if [[ -z "$best_crf" ]]; then
  echo "没有找到既达到 SSIM 门槛又比原片小的版本；保留原片。" >&2
  exit 2
fi

output="$OUTPUT_DIR/${name%.*}_${CODEC}_crf${best_crf}${output_suffix}.mp4"
if [[ -e "$output" ]]; then
  echo "达标成品已存在: $output"
  exit 0
fi
mv "$tmpdir/crf${best_crf}.mp4" "$output"
echo "完成: $output (SSIM $best_score, $best_bytes / $source_bytes bytes)"
