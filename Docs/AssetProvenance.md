# 素材来源与替换

## 已提供素材

`sucai/` 中的120张 PNG为用户提供的蓝湖设计配套素材，原文件名和像素保持不变。`AssetMapping.json` 记录97项语义映射及尺寸；77项映射当前入包，20项未使用导出图仅保留在原始素材目录。第二轮对齐恢复原始Join按钮，新增动态关注/已关注语义映射。AppIcon从用户提供的 `image 75@2x.png` 转为不透明1024像素 PNG；没有重画吉祥物。

按钮图片自带文字时不叠加相同文字。个人中心四个快捷入口使用原始整组 `Group 918@2x.png`，在原图上设置原生透明点击区域。签到页通过原生显示裁切完整设计背景，不重绘插画。

`Scripts/import_assets.py` 需要 Python 与 Pillow，用于复制已有素材、生成对应 Asset Catalog 声明以及导出 AppIcon。它不会生成图标插画，也不修改 `sucai` 原图。再次执行会保持两个原创补充图片目录。

## 原创补充图片

使用 Garden / gpt-image-2 的 Host-Native 流程，通过内置图像生成工具制作，2026-10-13导入。

| 资源 | 用途 | 制作说明（非工具请求逐字副本） |
| --- | --- | --- |
| wardrobe-placeholder | 用户大图、相册、内容照片及缺失媒体占位 | 粉色服装工作室、衣架与围巾，无人物、无文字，柔和材质，适配粉紫穿搭主题 |
| party-background | 深色语音房与通话背景 | 深紫时尚音乐空间、霓虹细节与心形装饰，无人物、无文字，中部预留原生内容空间 |

两个资源的 PNG 均位于 `Tutu/Resources/Assets.xcassets/<资源名>.imageset/artwork.png`。未使用外部人物图库或网络视频。未使用 SF Symbols 或代码绘制替代图标插画。

## 内容占位清单

2026-10-14接入用户提供的 `picss/` 74张JPEG与 `videoss/` 12个MP4，原文件字节不变。运行副本在 `Resources/Content/`；每个视频通过ffmpeg提取0.5秒处的JPEG封面。`Docs/ContentMapping.json`记录源文件、资源名、人物ID和SHA-256；`Scripts/import_content.py`可重复导入。全部媒体均在Discover、个人主页/相册或视频详情中有入口，未仅复制入包而不使用。

未根据面孔猜测跨照片身份。无明确对应关系的媒体分成86个独立条目，显示名是本地编辑别名，非素材人物的真实身份声明；头像、大图、相册与动态使用该条目自己的照片/视频封面。原Mia/Lily等6个稳定ID继续保留。人物资料不添加推测的国家或性别。无图片的用户草稿仍可用衣橱占位图。

开源字体：Google Fonts官方仓库 `ofl/outfit`，SIL OFL 1.1。原始可变字体及许可证保留于 `Resources/Fonts`；从原字体实例化400/500/600/700四个字重，内部名称为Tutu Outfit，未改变字形，UIAppFonts注册各实例。见 `Typography.swift`。

新增原创图片通过Garden/Image 2 Host-Native生成：`welcome-wardrobe`（粉紫衣橱礼箱、丝带与星币），`runway-frame`（铬银粉色丝带头像框，透明中心）。PNG在对应Asset Catalog imageset；提示词保存在 `garden-gpt-image-2/prompt`。动效仅对图片做原生位移/旋转/缩放，未用代码绘制替代插画。


照片取消选择不会覆盖当前图像。照片最多20MB，视频最多40MB/拍摄时长60秒；媒体体积上限是本地导入限制，不是上传服务协议。

## 包含范围

仅 `Tutu/` 内 Swift、Info、entitlements 和明确配置的 `Resources` 进入工程目标。`Docs`、`Scripts`、`README`、`sucai` 及图像生成说明不进入 App 的资源阶段。资源源文件体积与最终 IPA、App Store 下载、安装体积无等价关系。
