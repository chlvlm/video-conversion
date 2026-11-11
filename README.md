# video-conversion

将本地视频转为 HLS（`.m3u8` + `.ts`），供官网产品页等场景在线播放。

## 目录结构

```text
video-conversion/
├── source/              # 放入待转换的源视频
├── m3u8/                # 转换结果输出目录
│   └── <视频名>/
│       ├── <视频名>.m3u8
│       ├── <视频名>_000.ts
│       ├── <视频名>_001.ts
│       └── ...
├── video-to-m3u8.sh     # 转换脚本
└── README.md
```

## 依赖

需要本机已安装 FFmpeg（含 `ffmpeg` / `ffprobe`）：

```bash
brew install ffmpeg
```

## 使用方法

### 压缩为 MP4

批量压缩 `source/` 中除 `f8.mp4` 外的 MP4，并自动备份当前成品：

```bash
./compress-all.sh
```

默认 HEVC、CRF 24；如需更保画质，可运行 `./compress-all.sh --crf 22`。也可用 `--codec` 调整编码。新成品放在 `compressed/` 根目录，旧成品放在带时间戳的 `previous_.../` 子目录。该入口使用固定参数一次编码，保证每个输入都有成品，但它属于有损压缩，仍需查看暗部和细字。

单独压缩某段视频，或使用自动相似度门槛：

```bash
./compress-video.sh c10_banner.mp4
# 需要 H.264 播放兼容性时
./compress-video.sh c10_banner.mp4 --codec h264
# 更保画质
./compress-video.sh c10_banner.mp4 --crf 22
# 可选：按全片 SSIM 自动试压
./compress-video.sh c10_banner.mp4 --auto --min-ssim 0.997
```

输出位于 `compressed/`，文件名包含编码和 CRF 值，例如 `c10_banner_hevc_crf24.mp4`。单文件脚本默认使用 H.265/HEVC、CRF 24、`slow` 预设。加 `--auto` 才会试压 CRF 14–30：对完整视频计算 SSIM，只保留 SSIM 不低于 0.995 且比原片小的成品；找不到达标版本时保留原片。脚本保留原分辨率和帧率；如有音轨则编码为 AAC。已存在的输出文件不会被覆盖。SSIM 是相似度指标，不能保证肉眼完全无差异；最终使用前仍应检查暗部、细字和运动画面。HEVC 播放端需要支持 HEVC，网站发布前请用目标浏览器和设备验证。

### 转换为 HLS

1. 将源视频放到 `source/`（例如 `source/a8.mp4`）
2. 在项目根目录执行脚本

```bash
cd video-conversion

# 转换 source/ 下全部支持的视频（默认重编码）
./video-to-m3u8.sh

# 只转换指定文件
./video-to-m3u8.sh a8.mp4

# 自定义分片时长（秒）
./video-to-m3u8.sh a8.mp4 --hls-time 4

# 流复制模式（更快，分片可能不均匀）
./video-to-m3u8.sh a8.mp4 --copy
```

## 选项说明

| 选项 | 说明 |
|------|------|
| （无参数） | 转换 `source/` 下全部支持的视频 |
| `文件名...` | 只转换指定文件（优先从 `source/` 查找） |
| `--hls-time <秒>` | 分片时长，默认 `6` |
| `--copy` | 流复制，不重编码；更快，但分片可能不均匀 |
| `--reencode` | 强制重编码（默认行为，可省略） |
| `-h` / `--help` | 显示帮助 |

## 默认行为

- **默认重编码**为 H.264 / AAC，分片更均匀，浏览器兼容性更好，适合网站投放
- 批量扫描支持扩展名：`mp4` / `mov` / `mkv` / `webm` / `avi` / `m4v` / `flv` / `wmv` / `ts`
- 指定文件名时，只要 FFmpeg 能读即可转换
- 每次转换前会清理同名输出目录下旧的 `.m3u8` / `.ts` 分片

## 输出示例

输入：`source/a8.mp4`

输出：

```text
m3u8/a8/a8.m3u8
m3u8/a8/a8_000.ts
m3u8/a8/a8_001.ts
...
```

播放地址一般指向 playlist，例如：

```text
https://www.eversolo.com/Products/other/v/a8/a8.m3u8
```

上传时请把整个 `m3u8/<视频名>/` 目录一并部署，保证 `.m3u8` 与对应 `.ts` 分片在同一路径下可访问。

## 注意事项

- `--copy` 适合源视频本身已是 H.264/AAC、且只想快速试转；正式投放建议用默认重编码
- 源视频很大时，重编码会较慢，属正常现象
- 转换完成后，可用浏览器或 `MediaVideo` 组件验证 HLS 是否可播
