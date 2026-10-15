# Tutu · Prada 首轮交付

2026-10-15。当前项目输入：App ID `75252159`，API origin `https://fjnvs.fdhewhf.top`。本轮完成代码、部署文件、依赖解析和离线静态核对；没有编译、测试、启动 App、模拟器操作、业务 HTTP 探测、Ably 实连或真实购买。

## 控制台导入

仅导入这两个文件：

1. 选择 App ID **75252159**，在“接口管理”导入 [接口模板](generated/接口模板-75252159.json)。
2. 在“配置管理”导入 [配置模板](generated/配置模板-75252159.json)。
3. 校验并保存该 APP。`#{h5Url}`、`#{tokenResult}` 等平台占位符保持原样，由平台动态展开。

内容是只读配置。登录凭证验证、Ably 签名 TokenRequest、Apple 收据校验/幂等入账、实时回执确认和重放需要真实服务实现；固定 JSON 本身不实现这些能力。尤其付款响应的 `code:0` 只能在服务器校验原订单与 Apple 交易并完成持久入账后返回，不能用静态成功响应代替验单。

## 工程与协议

- 保留 SwiftUI、iOS 17、用户指定的 Bundle ID `com.tutustyleoutfit.lookbook`、团队 `JPTS6M4T5B`、iPhone-only、现有签名设置和 Release 运行 Scheme。原 `project.yml` 的旧 Bundle ID 已与实际工程同步。
- 已配置三个现有摄像头/麦克风/相册用途文案、Bundle ID URL Scheme、推送 entitlement。真机 APNs 仍需 Apple 开发者账号对应 App ID 与描述文件启用 Push Notifications；本轮没有操作开发者后台。
- 原工程无 SPM SDK。加入并锁定 Ably **1.4.0**、Alamofire **5.12.2**，`Package.resolved` 同时记录 delta-codec 1.3.5、msgpack 0.4.0。执行的 `xcodebuild -resolvePackageDependencies` 仅解析依赖，未构建。对应 Ably 的 `ARTTokenRequest.fromJson`、频道 options、订阅/发布与连接 API 已对照解析后的公开头文件；这不等于编译验证。
- 原创 UI 素材与原生布局保留；本轮仅调整已有欢迎页局部等待与纯文字支付遮罩。按 UI 路由读取 Claude Design，用于原生层级/反馈审阅；Taste 的网页重设计、Garden HTML/出图工作流不适用于本次既有素材的接入，不新造图标或 HTML。
- 唯一冻结来源为 `contract.json`。业务均为 POST JSON。登录方式、认证、静默恢复、续期共用版本 `look_edition`、APNs `ribbon_signal`、设备 `atelier_stamp` 三字符串和 `runway_delivery:2`。邮箱/Apple 仅主动认证时追加凭证；不持久化密码、Apple token 或 Ably token。

| 角色 | 路径 |
| --- | --- |
| 登录方式 | `/tutu/arrival/entry` |
| 认证/续期 | `/tutu/passport/fitting-pass` |
| 后台购买确认 | `/tutu/wallet/settlement` |
| 内容/人物/视频/评论 | `/tutu/catalog/editorial` |
| 直播与语音房 | `/tutu/catalog/rooms` |
| 礼物、金币包、风格、排名等 | `/tutu/catalog/atelier` |

`atelier_passage` 成功响应中的空字符串/空白表示 Apple、邮箱、注册；非空字符串表示仅游客；缺失、坏类型、未展开占位符或异常使用标准入口并在 Debug 标明 fallback。入口值不直接打开网页。邮箱/注册及游客通过认证接口成功后才选择或建立原本地资料；Apple 仍使用官方授权控件。

四个核心事件为 `RunwayDoorReady`、`WardrobeCheckout`、`AtelierSessionEnded`、`OpenStyleDestination`。字段路径、JSON 和 H5 字段映射均在双模板中。网页 origin 来自当前认证连接的合法页面事件，不使用 API host 作为白名单；首次页面 origin 用于相机/麦克风信任，iframe/其他 origin 拒绝。HTTP 页面仍受 iOS ATS 策略限制，建议后台配置 HTTPS；未加全局 ATS 放行。

## 数据完整性

保留源码快照在 `sources/`；`export_content.py` 从原始 JSON 与 Swift 常量离线导出，不调用 App。`source-manifest.json` 记录原文件 SHA256、记录顺序、ID 和媒体引用。旧 App 内 `EditorialCatalog.json` 已移出资源阶段，74 张供应照片和 12 个视频现使用用户指定的 R2 链接；12 张派生视频封面与原创风格素材保留在包内。素材维护脚本改为更新 Docs 来源与旧引用别名，不再复制媒体二进制或恢复内置业务数据。

最终接口响应包含 **86 条完整内容记录、24 个房间（6 视频 + 18 语音）、30 条评论、8 个礼物、9 个金币包、8 种风格、14 组穿搭问答主题、10 项排名**，以及原分类、文案、发现页顺序和人物统计。固定展示统计不冒充真实关系或真实在线人数。原金币奖励、付费回复等本地业务规则没有改金额。

三个内容 POST body 都是 `{}`，不等待 APNs、不携带登录参数。整批类型/ID/资源检查成功后，才原子替换 `Catalog.snapshot`；失败保留已有完整快照。首次没有内容时显示局部错误/重试，不使用打包 JSON 兜底。刷新不覆盖本地点赞、关注、评论、编辑资料、钱包等；原素材加载器支持 Bundle/Asset 与完整远程媒体 URL。

## 实际调用链静态记录（F01–F11）

| 项 | 文件/入口与调用者 | 静态结论及运行边界 |
| --- | --- | --- |
| F01 契约 | `contract.json` → 生成器 → `IntegrationContract.swift` / 双模板；`AtelierHTTP.response` | 六路径、七核心入参映射、三 H5 映射、四事件一致；无 datasetVersion。未探测部署。 |
| F02 内容 | `Gateway.reserve/reloadContent` → 三并行 POST → `AtelierSnapshot.validate` → `Catalog.snapshot` → 原页面 | 完整导出与最终内部 JSON 深比较一致；114 个媒体引用已分类核对（86 个远程地址、28 个本地封面/原创素材）；本地互动独立。未执行 Swift 解码/渲染。 |
| F03 工程 | `TutuApp` + `project.yml` → 实际 Xcode target | 33 个 Swift 文件在 Sources；Ably/Alamofire products 在 Frameworks；Info/entitlements plist 静态有效，原 build settings 未丢失。未编译/签名。 |
| F04 启动 | `AtelierAppDelegate` → `AtelierPush`；`StartupGateView.task` → `Gateway.start` → `detectEntry/authenticate` | 独立 reachability + 同源 HEAD；APNs continuation 最多 5 秒，取消恰好收尾、迟到 token 留下次；HTTP2xx/401 非空 data 优先 Ably，无有效 token 不降级 A。 |
| F05 入口 | `WelcomeView` → `reserve/email/guest/apple` → `finish` | 单锁覆盖 Apple 系统授权与后续阶段；游客协议默认勾选、可取消；局部动效尊重 Reduce Motion/前后台。赠币弹窗及触发状态已移除，原奖励保留。 |
| F06 Ably | `Gateway.connect` → `ConfiguredRealtimeTransport.start` | 强持有 client/channel，先绑定全消息订阅与状态，再 connect；频道来自签名 capability；首次 token 与单个续期、stop completion 接通；Debug 回调、Release 关闭敏感全文。实连未验收。 |
| F07 网页 | `prepareWeb` → 同一 `AtelierWebHost`/WKWebView → 当前 navigation 的有效 HTTP/MIME/didFinish + mounted | 初始化前设置 inline/AirPlay/autoplay；30 秒加载超时、失败/进程终止/重试；旧导航退役、失败停止加载；权限串行系统首授并逐项决定，未注入脚本。网页运行待验。 |
| F08 路由 | `Gateway.finish` 唯一提交 → `RootView` 仅 native 状态创建 MainTabs | 首次 connected 后 3 秒期限不因重连重置；空地址正常 A；坏地址独立错误；有效 B 主文档完成后直接呈现；A 决议开始后不再接受迟到启动 URL。静默恢复有 generation、取消与 activeProfile 校验。 |
| F09 购买 | 原 `WalletView.purchase` / 实时购买 → 唯一 `WalletService` → Keychain → 对应交付 → finish | 详见下节。只有交付状态回读成功后 finish；unknown 保留不猜测；30 秒商品查询/确认请求，有界 4/12/30 秒重试；启动 updates + unfinished 不依赖登录/内容。未触发购买。 |
| F10 现有业务 | `Gateway` 全消息 → `AtelierSocial` → 原 `ProfileState`/系统消息页/人物/动态 | 系统通知、版本化在线状态、增量动态、received/applied/displayed/read 回执、持久 outbox 与 60 秒重放请求接通；按 origin+channel+本地账号隔离。后端 ack/replay 未验收。原通话仅设备权限/本地预览，没有 RTC/接听入口，本轮不增加虚假来电连接。 |
| F11 生命周期 | `sessionEnded/reset`、expire、Scene 前后台、`.onOpenURL`、解锁通知 | 退出关连接/网页，取消旧登录/导航任务，清会话但不清设备/订单 Keychain；URL Scheme 仅唤醒；恢复交易不重新 purchase。未做杀进程/重装场景。 |

## 支付持久化与已知边界

`WalletService.start` 在登录前启动唯一 `Transaction.updates`，并枚举 `Transaction.unfinished`。前台、网络恢复、解锁及原生“检查待处理购买”均可触发恢复。订单 Keychain namespace 固定 `com.tutu.style.purchase-orders`，按属性枚举再逐条解码，坏记录保留隔离，存储失败不会当空库清除。

- 原生 `hostLocal`：付款前存模式、SKU、账号 UUID、walletInstance、版本/设备/App；保留原账号 UUID 的 appAccountToken 语义。通过 Apple 验签后，金币变更与 creditedTransactions/transactionGrants 在同一原子 profile 文件提交，再写/readback `localDelivered` 才 finish。
- 后台 `ablyServer`：付款前还冻结订单号、消息 ID、origin、确认路径和字段数组，appAccountToken 使用逐单 UUID。成功回放可由 UUID 找回原单；POST 仅五字符串 `look_edition / atelier_stamp / apple_stitch / receipt_fabric / checkout_thread`，收据是实际 App receipt 的 Base64，不是 JWS。HTTP2xx + 整数0后保存/readback `serverConfirmed` 才 finish，不调用本地充值。
- `processing` 按 App/环境/transactionId 合并；交互入口等待正在处理的同一交易，避免 Apple 返回早于确认时提前解除遮罩。商品查询及确认有有限超时，Apple 支付 sheet 不自行计时截断。取消/pending/失败或转待确认释放交互锁；待确认不表示到账。
- 原生历史已交付但没有新账本的交易，仅在原账号的可信 creditedTransactions 与 transactionGrants 存在时迁为 `localDelivered`，不从 SKU 猜来源。
- **原生关联缺口**：因为保留既有账号级 appAccountToken，若 Apple 成功与 transactionId 写入 Keychain 之间崩溃，且没有原子钱包交付证据，不能唯一推导该次原生订单。此时保留未完成交易待核对，不盲目匹配同 SKU。后台逐单 UUID 可恢复此窗口。历史提前 finish/丢关联的交易也不能保证追回。
- **重装边界**：Keychain 是否保留取决于同 App/访问配置/设备状态；本地消耗型余额不是 Keychain 订单记录。旧钱包文件丢失时，新 walletInstance 不接收旧单自动重发。`localDelivered` 只证明过去交付；不用于全量重建余额。未知、旧账号或证据丢失的交易保留，不能宣称无条件不丢单。
- 后台须按 App/环境/交易幂等并校验归属；确认响应丢失后客户端只重验原单，不再次购买。退出不销毁已提交 Apple 的单，也不会恢复旧账号登录；旧交易反馈不会弹到新账号。

## 扩展实时协议

见 [social-protocol.json](social-protocol.json)。这是服务开发约定，不是第三个控制台导入文件。双模板的四个固定槽保持原格式；扩展消息由真实服务在同一签名频道发布。无 ack/replay 服务时 outbox 保留，但不能宣称可靠离线补齐。

## 已执行与未执行

已执行：离线导出、最终双文件及其内部 JSON 解析/深比较、源 SHA256/ID/顺序核对、114 项媒体引用、target 成员和 SDK product 检查、权限/Scheme/plist 检查、XcodeGen 工程生成、SPM 依赖解析、`git diff --check`。维护命令：`python3 Docs/BackendAPI/audit_delivery.py`。

未执行：Swift 编译/类型检查/测试、模拟器或真机运行、线上接口、TokenRequest 签名有效性、Ably 会话/续期、WKWebView 真实页面/媒体授权、APNs 真机注册、StoreKit 沙盒/服务器到账、退出/重装恢复、视觉截图。已移除项目自有 Swift 的普通独立行注释，保留素材、许可证、部署来源与维护文档；没有修改其他项目。


## 2026-10-15 · CDN 媒体迁移

- 远程地址基址：`https://pub-1e78b29dc9034ab296832bae0193b76c.r2.dev/`。照片用 `pics/<原文件名>.jpg`；视频用 `videoss/<原文件名>.mp4`。它与业务 API 域名各自独立。
- `Docs/ContentMapping.json` 保留 86 条原始路径、资源名、人物 ID、原 SHA256，并增加 `remoteURL`。完整内容源、房间映射、主播相册与发现页配置同步替换。人物、房间、评论等数据的 ID、顺序和非媒体字段保持不变。
- `EditorialMediaAliases.json` 只包含旧资源路径到远程 URL 的映射，不包含人物业务数据。`AppStore.mediaURL` 和内容校验共用 `EditorialMedia.resolvedReference`，兼容本地旧头像、旧相册引用及仍返回旧资源名的后台配置。原始完整远程 URL 透传；用户自己保存的 `media/` 文件照旧本地读取。
- 图片继续走原有 `AsyncImage` 和原创占位图；视频由原播放器直接接收 HTTPS URL，保留单实例与生命周期。没有启动时全量下载，不增加永久媒体副本。系统仍可能为图片请求、播放缓冲使用临时缓存，不能理解成设备零存储。
- 已删除 `picss/`、`videoss/` 原文件及 `Resources/Content/` 内相应副本，共 172 个媒体文件、127,960,884 字节。其中移除安装包资源 63,980,442 字节（约 61.0 MiB），不代表最终压缩 IPA 的精确减幅。12 张视频首帧封面没有对应远程地址，保留本地约 1.5 MiB；原创 UI、礼物、背景及 8 张原创穿搭图保留。
- 删除前核对两份本地文件均匹配原 SHA256；86 个 R2 URL 的 HTTPS HEAD 均返回 200、正确 MIME，长度与原文件一致，12 个视频支持 bytes range。仅确认响应头，没有下载远端文件比较散列，也没有验证 App 内图片渲染或视频播放。记录在 `media-migration.json`。未请求业务接口、未编译或运行 App。
- 维护顺序：`python3 Scripts/import_content.py` → `python3 Docs/BackendAPI/export_content.py` → 使用原冻结契约重新生成模板 → `python3 Docs/BackendAPI/audit_delivery.py`。导入脚本现在从保留的映射和完整内容源工作，不依赖已删除的原始媒体目录。
- 后台导入本次更新的 **接口模板**；**配置模板**未改协议，可继续使用。客户端别名兼容也能处理之前模板中的旧 Bundle 路径。无需变更登录、支付、Ably 字段或事件契约。
