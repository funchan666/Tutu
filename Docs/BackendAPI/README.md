# Tutu · Prada 首轮交付

2026-10-15。当前项目输入：App ID `75252159`，API origin `https://fjnvs.fdhewhf.top`。本轮完成代码、部署文件、依赖解析和离线静态核对；没有编译、测试、启动 App、模拟器操作、业务 HTTP 探测、Ably 实连或真实购买。

## 控制台导入

仅导入这两个文件：

1. 选择 App ID **75252159**，在“接口管理”导入 [接口模板](generated/接口模板-75252159.json)。
2. 在“配置管理”导入 [配置模板](generated/配置模板-75252159.json)。
3. 校验并保存该 APP。`#{h5Url}`、`#{tokenResult}` 等平台占位符保持原样，由平台动态展开。

内容是只读配置。登录凭证验证、动态 WebSocket 连接信息、Apple 收据校验/幂等入账、实时回执确认和重放需要真实服务实现；固定 JSON 本身不实现这些能力。尤其付款响应的 `code:0` 只能在服务器校验原订单与 Apple 交易并完成持久入账后返回，不能用静态成功响应代替验单。

## 工程与协议

- 保留 SwiftUI、iOS 17、用户指定的 Bundle ID `com.tutustyleoutfit.lookbook`、团队 `JPTS6M4T5B`、iPhone-only、现有签名设置和 Release 运行 Scheme。原 `project.yml` 的旧 Bundle ID 已与实际工程同步。
- 已配置三个现有摄像头/麦克风/相册用途文案、Bundle ID URL Scheme、推送 entitlement。真机 APNs 仍需 Apple 开发者账号对应 App ID 与描述文件启用 Push Notifications；本轮没有操作开发者后台。
- 当前实时连接使用 Foundation `URLSessionWebSocketTask`。已移除 Ably 1.4.0 的 package/product/framework 和专属 delta-codec、msgpack 锁项；Alamofire 5.12.2、TPInAppReceipt 4.0.2 及其余锁定版本保留。本次未解析依赖或构建；锁文件保留其余原始 revision，Xcode 后续实际构建时仍需正常检查依赖图。
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
| F03 工程 | `TutuApp` + `project.yml` → 实际 Xcode target | 33 个 Swift 文件在 Sources；Alamofire/TPInAppReceipt products 在 Frameworks，原生传输沿用既有 Sources 成员；Info/entitlements plist 静态有效，原 build settings 未丢失。未编译/签名。 |
| F04 启动 | `AtelierAppDelegate` → `AtelierPush`；`StartupGateView.task` → `Gateway.start` → `detectEntry/authenticate` | 独立 reachability + 同源 HEAD；APNs continuation 最多 5 秒，取消恰好收尾、迟到 token 留下次；HTTP2xx/401 非空 data 优先解析既有连接槽位；连接配置错误不降级 A。 |
| F05 入口 | `WelcomeView` → `reserve/email/guest/apple` → `finish` | 单锁覆盖 Apple 系统授权与后续阶段；游客协议默认勾选、可取消；局部动效尊重 Reduce Motion/前后台。赠币弹窗及触发状态已移除，原奖励保留。 |
| F06 实时 | `Gateway.configuration/connect` → `ConfiguredRealtimeTransport.start/open/consume` → 原事件解码器 | `data.token` 对象或单层 JSON → 完整 wss 地址直连；action 4 原样 attach、11 ready、15 批消息；已有认证公共字段续期、空闲检测、退避、终态与代次清理。未实连。 |
| F07 网页 | `prepareWeb` → 同一 `AtelierWebHost`/WKWebView → 当前 navigation 的有效 HTTP/MIME/didFinish + mounted | 初始化前设置 inline/AirPlay/autoplay；30 秒加载超时、失败/进程终止/重试；旧导航退役、失败停止加载；权限串行系统首授并逐项决定，未注入脚本。网页运行待验。 |
| F08 路由 | `Gateway.connect/receive/finish`、`ConfiguredCoreEvent.pageDestination` | 首次 action 11 起最多 3 秒；早到消息暂存后分发；有效 B 取消计时，已提交 A 后迟到启动页不切换。无地址正常 A，坏地址/网页失败独立处理。未运行切页场景。 |
| F09 购买 | 原 `WalletView.purchase` / 实时购买 → 唯一 `WalletService` → Keychain → 对应交付 → finish | 详见下节。只有交付状态回读成功后 finish；unknown 保留不猜测；30 秒商品查询/确认请求，有界 4/12/30 秒重试；启动 SK1 observer + transactions 不依赖登录/内容。未触发购买。 |
| F10 现有业务 | `Gateway` 全消息 → `AtelierSocial` → 原 `ProfileState`/系统消息页/人物/动态 | 系统通知、版本化在线状态、增量动态、received/applied/displayed/read 回执、持久 outbox 与 60 秒重放请求接通；按 origin+channel+本地账号隔离。后端 ack/replay 未验收。原通话仅设备权限/本地预览，没有 RTC/接听入口，本轮不增加虚假来电连接。 |
| F11 生命周期 | `sessionEnded/reset`、expire、Scene 前后台、`.onOpenURL`、解锁通知 | 退出关连接/网页，取消旧登录/导航任务，清会话但不清设备/订单 Keychain；URL Scheme 仅唤醒；恢复交易不重新 purchase。未做杀进程/重装场景。 |

## 支付持久化与已知边界

`WalletService.start` 在登录前注册唯一 `SKPaymentTransactionObserver`，并枚举 `SKPaymentQueue.default().transactions`。商品查询使用 `SKProductsRequest`，价格来自 `SKProduct.price/priceLocale`，付款使用 `SKMutablePayment`。已移除 StoreKit 2 购买与交易监听。前台、网络恢复、解锁及原生“检查待处理购买”均可触发恢复。订单 Keychain namespace 固定 `com.tutu.style.purchase-orders`，按属性枚举再逐条解码，坏记录保留隔离，存储失败不会当空库清除。

- 原生 `hostLocal`：付款前存模式、SKU、账号 UUID、walletInstance、版本/设备/App；保留旧 accountToken 与账号归属；新单另存逐单 paymentUsername 并传入 SKMutablePayment.applicationUsername。通过 TPInAppReceipt 4.0.2 的 Apple 证书链、收据创建时间签名、设备哈希及 App 元数据验证，并核对交易号、SKU 和数量后，金币变更与 creditedTransactions/transactionGrants 在同一原子 profile 文件提交，再写/readback `localDelivered` 才 finish。
- 后台 `ablyServer`：付款前还冻结订单号、消息 ID、origin、确认路径和字段数组，新单 applicationUsername 使用逐单 UUID；旧后台单仍按原 accountToken UUID 恢复。成功回放可由 UUID 找回原单；POST 仅五字符串 `look_edition / atelier_stamp / apple_stitch / receipt_fabric / checkout_thread`，收据是实际 App receipt 的 Base64，不是 JWS。HTTP2xx + 整数0后保存/readback `serverConfirmed` 才 finish，不调用本地充值。
- `processing` 按 App/transactionId 串行消费，已付款后从已验签收据确定环境并与原单比对；同交易存在多个环境/订单关联时隔离，不猜测。交互锁保留到本单回调处理结束，重复回调不会提前解除遮罩。商品查询及确认有有限超时，Apple 支付 sheet 不自行计时截断。取消/deferred/失败或转待确认释放交互锁；待确认不表示到账。
- 原生历史已交付但没有新账本的交易，仅在原账号的可信 creditedTransactions 与 transactionGrants 存在时迁为 `localDelivered`，不从 SKU 猜来源。
- **历史原生关联缺口**：旧版账号级 appAccountToken 没有被重写，旧单若在 Apple 成功与 transactionId 落盘之间崩溃、又没有原子钱包交付证据，仍不能唯一推导订单。新单的 applicationUsername 单独保存逐单 UUID，可在 Apple 回放保留该值时关联；若 Apple 回放缺绑定且账本没有 transactionId，则保留待核对，不盲目匹配同 SKU。历史提前 finish/丢关联的交易也不能保证追回。
- **重装边界**：Keychain 是否保留取决于同 App/访问配置/设备状态；本地消耗型余额不是 Keychain 订单记录。旧钱包文件丢失时，新 walletInstance 不接收旧单自动重发。`localDelivered` 只证明过去交付；不用于全量重建余额。未知、旧账号或证据丢失的交易保留，不能宣称无条件不丢单。
- **SK1 验证与退款边界**：仅接受 Apple Production/Sandbox 收据，不接受 Xcode/LocalTesting 收据兜底。原目录九个 SKU 仍须在 App Store Connect 配成消耗品；SKProduct 无商品类型属性，receipt 类型存在时复核、旧收据未知类型不伪称已确认。启动与前台可检查已签名收据中的撤销记录，原钱包幂等冲销；已 finish 的消耗品可能不再留在收据，且 SK1 不提供等价的消耗品退款实时流，完整退款对账需要服务端 Apple 通知。依赖新增的最终包体增量尚未归档测量。
- 后台须按 App/环境/交易幂等并校验归属；确认响应丢失后客户端只重验原单，不再次购买。退出不销毁已提交 Apple 的单，也不会恢复旧账号登录；旧交易反馈不会弹到新账号。

## 扩展实时协议

见 [social-protocol.json](social-protocol.json)。这是服务开发约定，不是第三个控制台导入文件。双模板的四个固定槽保持原格式；扩展消息由真实服务在同一签名频道发布。无 ack/replay 服务时 outbox 保留，但不能宣称可靠离线补齐。

## 已执行与未执行

已执行：离线导出、最终双文件及其内部 JSON 解析/深比较、源 SHA256/ID/顺序核对、114 项媒体引用、target 成员和 SDK product 检查、权限/Scheme/plist 检查、XcodeGen 工程生成、SPM 依赖解析、`git diff --check`。维护命令：`python3 Docs/BackendAPI/audit_delivery.py`。

本次 StoreKit 1 迁移仅完成依赖解析、源码/API 对照及离线配置核对；未执行购买。支付接口、商品 ID 和双模板保持不变，无需为此次迁移重新导入控制台。

未执行：Swift 编译/类型检查/测试、模拟器或真机运行、线上接口、动态连接信息有效性、原生 WebSocket 会话/续期、WKWebView 真实页面/媒体授权、APNs 真机注册、StoreKit 沙盒/服务器到账、退出/重装恢复、视觉截图。已移除项目自有 Swift 的普通独立行注释，保留素材、许可证、部署来源与维护文档；没有修改其他项目。


## 2026-10-15 · CDN 媒体迁移

- 远程地址基址：`https://pub-1e78b29dc9034ab296832bae0193b76c.r2.dev/`。照片用 `pics/<原文件名>.jpg`；视频用 `videoss/<原文件名>.mp4`。它与业务 API 域名各自独立。
- `Docs/ContentMapping.json` 保留 86 条原始路径、资源名、人物 ID、原 SHA256，并增加 `remoteURL`。完整内容源、房间映射、主播相册与发现页配置同步替换。人物、房间、评论等数据的 ID、顺序和非媒体字段保持不变。
- `EditorialMediaAliases.json` 只包含旧资源路径到远程 URL 的映射，不包含人物业务数据。`AppStore.mediaURL` 和内容校验共用 `EditorialMedia.resolvedReference`，兼容本地旧头像、旧相册引用及仍返回旧资源名的后台配置。原始完整远程 URL 透传；用户自己保存的 `media/` 文件照旧本地读取。
- 图片继续走原有 `AsyncImage` 和原创占位图；视频由原播放器直接接收 HTTPS URL，保留单实例与生命周期。没有启动时全量下载，不增加永久媒体副本。系统仍可能为图片请求、播放缓冲使用临时缓存，不能理解成设备零存储。
- 已删除 `picss/`、`videoss/` 原文件及 `Resources/Content/` 内相应副本，共 172 个媒体文件、127,960,884 字节。其中移除安装包资源 63,980,442 字节（约 61.0 MiB），不代表最终压缩 IPA 的精确减幅。12 张视频首帧封面没有对应远程地址，保留本地约 1.5 MiB；原创 UI、礼物、背景及 8 张原创穿搭图保留。
- 删除前核对两份本地文件均匹配原 SHA256；86 个 R2 URL 的 HTTPS HEAD 均返回 200、正确 MIME，长度与原文件一致，12 个视频支持 bytes range。仅确认响应头，没有下载远端文件比较散列，也没有验证 App 内图片渲染或视频播放。记录在 `media-migration.json`。未请求业务接口、未编译或运行 App。
- 维护顺序：`python3 Scripts/import_content.py` → `python3 Docs/BackendAPI/export_content.py` → 使用原冻结契约重新生成模板 → `python3 Docs/BackendAPI/audit_delivery.py`。导入脚本现在从保留的映射和完整内容源工作，不依赖已删除的原始媒体目录。
- 后台导入本次更新的 **接口模板**；**配置模板**未改协议，可继续使用。客户端别名兼容也能处理之前模板中的旧 Bundle 路径。无需变更登录、支付、Ably 字段或事件契约。



## 2026-10-15 · Prada 差异同步：原生 WebSocket

本次是已有接入的增量更新。App ID `75252159`、origin、六个接口路径、请求字段、事件名、登录方式、业务数据、媒体、StoreKit 1、商品、订单 Keychain 命名空间和补单逻辑保持原值。没有重新接入、请求业务接口、连接实时服务、编译、类型检查、测试或启动 App。

- 地址来源仍为 `/tutu/passport/fitting-pass` 的 `data.token = #{tokenResult}` 动态槽位。客户端支持对象或单层 JSON 字符串，其中需含完整 `wss` URL 和 `attach` 对象；可选 `roomId/clientId/expiresAt` 按类型、身份及毫秒到期时间校验。频道读取服务端 attach.channel，并与订阅确认保持一致。这里说明客户端支持的输入结构，不表示已观察到线上 tokenResult；未展开占位符、旧 TokenRequest、缺 URL/attach 明确失败，不正常进入 A。
- `ConfiguredRealtimeTransport` 为唯一 MainActor 连接所有者，URL 原样交系统；不增取地址接口、HTTP 头、subprotocol、AES、URL 参数或固定 rewind。`contract.realtime.transport = "rtLink"` 仅为技能兼容标记，不是接口调用。历史 `ablyClientID/ablyServer` 名称保持身份及账本含义。
- action 4 发送服务端 attach；11 才 ready；15 全批逐条规范化，坏条目不影响后续条目。沿用原 SDK 的消息 ID 规则：有 message.id 则直接使用，否则仅在实际 frame.id 存在时用 frame.id 与批内索引组成 ID；两者缺失不伪造 ID。依据见 [原 SDK 的消息分发](https://github.com/ably/ably-cocoa/blob/1.4.0/Source/ARTRealtimeChannel.m)。订阅前消息在同代内有界暂存，ready 后交原发送方过滤、去重和事件处理。首次 ready 开始三秒路由等待，重连不重启期限。
- 接收任意帧重置服务端 maxIdleInterval 加五秒 watchdog；连接/订阅有十五秒期限。重连按 1、2、4、8、16、30 秒基准加抖动，只有订阅成功清零。action 8 停止自动重连，前台/网络恢复不绕过终态；退出或新登录取消 socket、收发、刷新、订阅、续期、重连及 ACK 等待。
- 到期元数据存在时提前刷新，短有效期避免零间隔循环；健康连接续期或 action 17 先取新信息再切换，期间若连接断开则关闭旧 socket 并复用同一刷新任务。凭证失效与断线同样复用现有认证公共字段刷新来源，不重放密码/Apple 凭证。该来源原已有续期调用，继续遵守最多五秒 APNs 等待、HTTP 超时和登录 attempt 约束；相同会话频道和已有 roomId 不允许在刷新中漂移。没有额外 rtLink 调用或套用其限流规则。
- `AtelierSocial.flush/sync` 的原事件和 payload 保留。原生上行按 [Ably 官方协议](https://github.com/ably/specification/blob/main/specifications/protocol.md) 使用 action 15/channel/msgSerial 与 JSON encoding；每帧一条，单连接序列分配并串行发送。action 1/2 对应传输 ACK/NACK，覆盖范围、重复确认及跳号处理；二十秒未确认、发送失败、断线、stop 均失败收尾。socket.send 成功不等于服务端确认；传输 ACK 不删除业务 outbox，只有原 `AtelierReceiptAccepted` 才删除持久回执。支付仍独立走原五字段 HTTP 验单与 Keychain 终态回读。
- `ConfiguredEventDecoder.externalURL` 已符合最新版规则：绝对 URL 检查后交系统打开，不使用网页专属 HTTP(S) 白名单。现有 APNs 五秒等待、权限声明与 bid Scheme、局部登录反馈、WebView 媒体权限合并、支付纯文字遮罩均保留，未做视觉改动。
- 本次静态检查覆盖源码接线、工程成员、依赖产品与锁项、JSON/plist、双模板与源数据一致性、差异空白及支付源码未变。已更新原离线审计工具的依赖断言；没有新增运行测试。此前执行记录属于对应历史交付，不代表本次再次运行。

**部署与未验证项**：两个后台导入 JSON 的内容未改变，无需因本次客户端更新重新导入。线上实际连接载荷、attach 的订阅/发布权限、刷新响应、原生收发及 ACK、前后台恢复、网页/APNs/真实支付均未联调。私有网关若与标准发布协议有差异，需在后续获准联调时确认，不能由静态核对保证服务支持。

## 2026-10-15 · 登录错误定位与后端直连返回要求

用户授权对现有登录接口做最小范围线上排查，并明确选择保持地址直连、由后台返回 `url` 和 `attach`；不恢复 Ably SDK、不增加客户端旧 TokenRequest 换票请求、不调用 rtLink。以下记录更新上节“线上载荷未验证”的范围，不代表原生 App 登录全链路已经通过。

- 使用独立诊断安装标识、当前应用版本和既有四个公共请求字段请求 `/tutu/passport/fitting-pass`，APNs token 为空；未使用用户 Apple/邮箱凭证，也未操作用户现有会话。这是接口结构排查，不等于截图中同一账号的登录复现。
- 实际 HTTP 200、业务 code 0；`data.token` 是含 `keyName/nonce/mac/capability/timestamp/ttl/clientId` 的旧 TokenRequest 对象，clientId 为 app，没有 `url/attach`。当前原生直连解析器无法消费该结构。这与迁移前 SDK 消费 TokenRequest 的方式不同，说明线上返回与迁移后的客户端输入契约不兼容。
- 原 `ConfiguredRealtimeError` 没有 LocalizedError 描述，界面因此暴露 Swift 错误域和错误0。客户端现已区分旧票据、URL、订阅、身份、到期时间等失败原因；Debug 只记录固定错误类别，界面使用可读错误提示。不记录票据、连接 URL、签名、频道或完整响应。

### 后端需要修改的内容

保留 App ID `75252159`、现有域名、认证路径和公共请求字段。修改实际生成 `#{tokenResult}` 的服务逻辑，使认证和现有刷新调用均返回以下结构；不是在控制台填入一次性的静态连接地址。

| 响应位置 | 要求 |
| --- | --- |
| `data.token` | JSON 对象，或一层编码该对象的 JSON 字符串；不额外包 `result` 层，不返回旧 TokenRequest。 |
| `data.token.url` | 当前会话真实可用、完整的 `wss://` URL，鉴权参数由服务端生成；不返回占位符，不依赖客户端补 URL、Header 或再次请求 rtLink。 |
| `data.token.attach` | 完整订阅 JSON 对象，`action` 为整数 10、`channel` 为当前会话实际授权的非空频道。客户端在 action 4 后原样发送。 |
| `data.token.clientId` | 可省略；若返回，必须是字符串 `app`。 |
| `data.token.roomId` | 可省略；若返回，必须是非空字符串，同一会话刷新时保持一致。 |
| `data.token.expiresAt` | 可省略；若返回，必须是未来时间的 Unix 毫秒数，不能用秒或数字字符串。 |

服务端继续在对应频道发送既有 `RunwayDoorReady` 等业务事件，保留原发送方、消息格式和支付逻辑。若既有业务依赖历史首条路由消息，需由后端在 attach 中提供对应订阅参数，或在订阅后发送；客户端不擅自固定 rewind。刷新必须继续提供同一会话的新有效地址及相同频道。

订阅动作依据：[Ably 原生连接与 attach 协议](https://ably.com/blog/how-to-connect-to-ably-directly-part-1)。旧 TokenRequest 是用于取得访问凭证的签名请求，不是完整连接地址；两者不能互换。

**交付边界**：本仓库未包含后端服务实现，因此未修改线上 tokenResult 生成逻辑。既有导入模板仍保留动态 `#{tokenResult}`，无需重复导入当前未变化的模板。当前只完成失败分类、可读提示和静态差异检查；登录恢复仍取决于后台完成上述变更。未编译、未运行自动化测试、未建立诊断 WebSocket、未触发购买或修改后台配置。后端更新后需核对新响应并按授权验证订阅和登录结果。
