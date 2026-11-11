#!/usr/bin/env bash
# 一条命令压缩 source/ 下除 f8 外的 MP4，并归档上一次的成品。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$ROOT/source"
OUTPUT_DIR="$ROOT/compressed"
CRF=24
CODEC=hevc

usage() {
  cat <<'EOF'
用法: ./compress-all.sh [--crf 14-30] [--codec hevc|h264]

默认压缩 source/ 下除 f8.mp4 外的所有 MP4，使用 HEVC、CRF 24。
运行前将 compressed/ 根目录中的旧 MP4 移到带时间戳的备份目录。
CRF 越小画质越高、文件通常越大；这是有损压缩，不能保证逐像素相同。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --crf)
      if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi
      CRF="$2"
      shift 2
      ;;
    --codec)
      if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi
      CODEC="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! "$CRF" =~ ^(1[4-9]|2[0-9]|30)$ || ( "$CODEC" != hevc && "$CODEC" != h264 ) ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "缺少 source 目录: $SOURCE_DIR" >&2
  exit 1
fi

inputs=()
for input in "$SOURCE_DIR"/*.mp4; do
  [[ -f "$input" ]] || continue
  [[ "${input##*/}" == f8.mp4 ]] && continue
  inputs+=("$input")
done
if [[ ${#inputs[@]} -eq 0 ]]; then
  echo "没有需要压缩的 MP4" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
backup_dir="$OUTPUT_DIR/previous_$(date +%Y%m%d_%H%M%S)_$$"
for old in "$OUTPUT_DIR"/*.mp4; do
  [[ -f "$old" ]] || continue
  mkdir -p "$backup_dir"
  mv "$old" "$backup_dir/"
done
if [[ -d "$backup_dir" ]]; then
  echo "旧版备份: $backup_dir"
fi

echo "本次编码: $CODEC, CRF $CRF"
for input in "${inputs[@]}"; do
  name="${input##*/}"
  echo "压缩: $name"
  "$ROOT/compress-video.sh" "$input" --codec "$CODEC" --crf "$CRF"
done

echo "全部完成。新成品位于: $OUTPUT_DIR"
