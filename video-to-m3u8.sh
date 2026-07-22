#!/usr/bin/env bash
# 视频 → HLS (m3u8 + ts)
# 源视频: ./source/
# 输出:   ./m3u8/<视频名>/<视频名>.m3u8
#
# 用法:
#   ./video-to-m3u8.sh                 # 转换 source 下全部视频（默认重编码）
#   ./video-to-m3u8.sh a8.mp4          # 只转换指定文件
#   ./video-to-m3u8.sh --copy          # 可选：流复制（更快，分片可能不均匀）
#   ./video-to-m3u8.sh a8.mp4 --hls-time 4

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$ROOT/source"
OUTPUT_DIR="$ROOT/m3u8"
SCRIPT_NAME="$(basename "$0")"

# 批量扫描时识别的扩展名
VIDEO_EXTS=(-iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.avi' -o -iname '*.m4v' -o -iname '*.flv' -o -iname '*.wmv' -o -iname '*.ts')

# 网站投放默认强制重编码，分片更均匀、兼容性更好
MODE="reencode"
HLS_TIME=6
TARGETS=()

usage() {
  cat <<EOF
用法: ${SCRIPT_NAME} [文件名...] [选项]

说明:
  从 source/ 读取视频，输出到 m3u8/<视频名>/<视频名>.m3u8
  默认强制重编码为 H.264/AAC（适合网站投放，分片更均匀）
  不传文件名时转换 source/ 下全部支持的视频
  批量扫描: mp4 / mov / mkv / webm / avi / m4v / flv / wmv / ts
  指定文件名时可转换任意 FFmpeg 能读取的格式

选项:
  --copy           流复制（较快，但分片可能不均匀）
  --hls-time <秒>  分片时长，默认 6
  -h, --help       显示帮助

示例:
  ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} a8.mp4
  ./${SCRIPT_NAME} --hls-time 4
  ./${SCRIPT_NAME} a8.mp4 --copy
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --copy)
      MODE="copy"
      shift
      ;;
    --reencode)
      # 兼容旧参数；默认已是重编码
      MODE="reencode"
      shift
      ;;
    --hls-time=*)
      HLS_TIME="${1#*=}"
      shift
      ;;
    --hls-time)
      if [[ $# -lt 2 ]]; then
        echo "缺少 --hls-time 参数" >&2
        usage
        exit 1
      fi
      HLS_TIME="${2:?缺少 --hls-time 参数}"
      shift 2
      ;;
    -*)
      echo "未知选项: $1" >&2
      usage
      exit 1
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if [[ ! "$HLS_TIME" =~ ^[1-9][0-9]*$ ]]; then
  echo "--hls-time 必须是正整数秒数: $HLS_TIME" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "未找到 ffmpeg，请先安装: brew install ffmpeg" >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "未找到 ffprobe，请先安装: brew install ffmpeg" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "缺少 source 目录: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

collect_inputs() {
  local files=()
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( "${VIDEO_EXTS[@]}" \) -print0 | sort -z)
  else
    local name path
    for name in "${TARGETS[@]}"; do
      if [[ "$name" == /* ]]; then
        path="$name"
      elif [[ -f "$SOURCE_DIR/$name" ]]; then
        path="$SOURCE_DIR/$name"
      elif [[ -f "$name" ]]; then
        path="$(cd "$(dirname "$name")" && pwd)/$(basename "$name")"
      else
        echo "文件不存在: $name（请放在 source/ 下）" >&2
        exit 1
      fi
      files+=("$path")
    done
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "source/ 中没有可转换的视频" >&2
    exit 1
  fi

  printf '%s\0' "${files[@]}"
}

video_fps() {
  local input="$1"
  local rate fps

  rate="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=avg_frame_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    "$input" | head -n 1)"

  fps="$(awk -F/ '
    NF == 2 && $1 > 0 && $2 > 0 { printf "%d\n", ($1 / $2) + 0.5; next }
    NF == 1 && $1 > 0 { printf "%d\n", $1 + 0.5; next }
  ' <<<"$rate")"

  if [[ ! "$fps" =~ ^[1-9][0-9]*$ ]]; then
    fps=25
  fi

  printf '%s\n' "$fps"
}

convert_one() {
  local input="$1"
  local basename name outdir playlist segment_pattern fps gop_frames

  basename="$(basename "$input")"
  name="${basename%.*}"
  outdir="$OUTPUT_DIR/$name"
  playlist="$outdir/$name.m3u8"
  segment_pattern="$outdir/${name}_%03d.ts"
  fps="$(video_fps "$input")"
  gop_frames=$((fps * HLS_TIME))

  mkdir -p "$outdir"
  find "$outdir" -maxdepth 1 \( -name "${name}_*.ts" -o -name 'index_*.ts' -o -name 'seg_*.ts' -o -name "$name.m3u8" -o -name 'index.m3u8' \) -delete

  echo "========"
  echo "输入: $input"
  echo "输出: $playlist"
  echo "分片: ${HLS_TIME}s"
  echo "帧率: ${fps}fps"
  echo "模式: $([[ "$MODE" == "reencode" ]] && echo '重编码 H.264/AAC' || echo '流复制 copy')"
  echo

  if [[ "$MODE" == "reencode" ]]; then
    ffmpeg -y -i "$input" \
      -map 0:v:0 -map 0:a? -sn -dn \
      -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
      -g "$gop_frames" -keyint_min "$gop_frames" -sc_threshold 0 \
      -force_key_frames "expr:gte(t,n_forced*$HLS_TIME)" \
      -c:a aac -b:a 128k -ac 2 \
      -hls_time "$HLS_TIME" \
      -hls_list_size 0 \
      -hls_playlist_type vod \
      -hls_flags independent_segments \
      -hls_segment_filename "$segment_pattern" \
      "$playlist"
  else
    ffmpeg -y -i "$input" \
      -map 0:v:0 -map 0:a? -sn -dn \
      -c:v copy -c:a copy \
      -hls_time "$HLS_TIME" \
      -hls_list_size 0 \
      -hls_playlist_type vod \
      -hls_flags independent_segments \
      -hls_segment_filename "$segment_pattern" \
      "$playlist"
  fi

  local count
  count="$(find "$outdir" -name "${name}_*.ts" | wc -l | tr -d ' ')"
  echo
  echo "完成: ${playlist}（${count} 个分片）"
  echo
}

echo "工作目录: $ROOT"
echo "源目录:   $SOURCE_DIR"
echo "输出目录: $OUTPUT_DIR"
echo

while IFS= read -r -d '' input; do
  convert_one "$input"
done < <(collect_inputs)

echo "全部完成。"
