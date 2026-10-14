# Tutu

原生 SwiftUI iPhone 项目，最低 iOS 17，竖屏。工程名和应用显示名为 Tutu，保留用户提供的 GlowStyle 欢迎页品牌素材。

设计依据：蓝湖「海外A面19 → 211（穿搭直播）」；原始素材位于 `sucai/`。主导航为 Style Live、Party、Create Your Look、Discover、Profile。应用页面不使用“预览”“演示”作为产品状态文案。

## 打开项目

打开 `Tutu.xcodeproj`，Scheme 为 `Tutu`。配置来源是 `project.yml`，需要更新工程文件时运行 `xcodegen generate`。这只生成工程，不代表编译成功。

当前 Bundle ID 为 `com.tutu.style`，未填写开发团队；正式签名、Sign in with Apple 能力、App Store Connect 商品需要按实际账号配置。启用设备端 AI Stylist 需要 Xcode 26 SDK，运行端需要支持 Apple Intelligence 的 iOS 26 设备及可用模型。其余页面部署目标仍为 iOS 17。

## 当前交付边界

本地交互与状态保存已实现：账号创建/登录、资料、照片/视频导入、动态与评论保存、关注/拉黑、搜索筛选、七日签到、积分等级、金币账本、礼物购买与背包、草稿、房间设置、原生权限、退出及删除本机账号。

真实服务尚未连接：跨设备账号、用户间消息和通话、直播、礼物远程送达、云端余额与内容分发。相关操作保留输入或物品并显示可重试的不可用状态，不伪造发送或接听成功。已接入用户提供的74张图片和12个视频，目录人物为本地内容资料。

StoreKit 2 按用户点击单个商品时读取对应Apple商品，再调用原生购买；仅验签成功且账户匹配的交易入账，持久化完成后才finish。9档商品及美元价格见 `Docs/IAPProducts.csv`，新增两档仍需在App Store Connect创建。未完成真实沙盒交易验收。本地金币可解锁原创头像框、收藏并佩戴礼物挂件；远程送礼不可用。当前钱包没有跨设备同步或服务端结算。

AI Stylist 调用 Apple Foundation Models 的真实本机模型，当前为文字穿搭建议；上传照片仅供用户参考，不会伪称模型已识图。不支持模型的设备会保留问题并提示不可用。

举报保存草稿并允许用户通过原生 Mail 编辑器发送到已发布协议中的安全邮箱；不将本地保存、交给 Mail 或取消发送声称为平台受理。

## 文档

- [页面与功能交接](Docs/ImplementationStatus.md)
- [素材来源与替换](Docs/AssetProvenance.md)
- [内购商品配置](Docs/IAPProducts.csv)
- [静态检查结果](Docs/StaticReview.md)
- [模拟器截图与设计差异](Docs/SimulatorReview.md)
- [素材映射](Docs/AssetMapping.json)

2026-10-13经用户明确要求，已在开启的 iPhone 18 Pro / iOS 27.0 模拟器编译、安装、启动并截图五个主界面，详情见模拟器核对记录。未执行自动化测试或真机验收，没有生成 IPA。

同日第二轮已修正主要布局差异并重新运行检查；[最新五页截图总览](output/design-aligned-2026-10-13/main-screens.jpg)与原始PNG均已保存。完整差异状态、尚缺素材和未验收范围见[核对记录](Docs/SimulatorReview.md)。

2026-10-14更新：新增账号首次进入首页赠送360金币并展示原创欢迎动效；聊天、AI聊天、语音和视频聊天均免费。接入Outfit开源字体及74张照片、12个视频。详情见[金币与素材交接](Docs/ImplementationStatus.md)。本轮按默认约定仅做静态核对，未编译、运行或测试。
