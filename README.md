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
