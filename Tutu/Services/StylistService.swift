import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct StylistReply {
    let text: String
    let source: String
}
struct StyleDirection: Identifiable {
    let name: String
    let image: String
    let detail: String
    var id: String { name }
    // Original Tutu lookbook artwork; independent of user-supplied content photos.
    static let all = [
        StyleDirection(name: "Minimalist", image: "stylist-minimalist", detail: "Clean lines, quiet tones"),
        StyleDirection(name: "Streetwear", image: "stylist-streetwear", detail: "Relaxed proportions"),
        StyleDirection(name: "Vintage", image: "stylist-vintage", detail: "Character in every layer"),
        StyleDirection(name: "Soft Tailoring", image: "stylist-soft-tailoring", detail: "Structure, softened"),
        StyleDirection(name: "Smart Casual", image: "stylist-smart-casual", detail: "Easy, polished essentials"),
        StyleDirection(name: "Cozy", image: "stylist-cozy", detail: "Texture and comfort"),
        StyleDirection(name: "City Chic", image: "stylist-city-chic", detail: "A little everyday drama"),
        StyleDirection(name: "Weekend", image: "stylist-weekend", detail: "Off-duty favorites")
    ]
}
enum StylistService {
    static var modelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }
    static func reply(to message: String, style: String, occasion: String, history: [ConversationMessage]) async throws -> StylistReply {
        try Task.checkCancellation()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let instructions = """
            You are GlowStyle's kind, concise fashion stylist. Give useful clothing and colour pairing advice in the user's language. Respond in at most 160 words, with a short outfit formula and one practical finishing detail. Ask a short clarifying question when needed. Never imply you can see an uploaded photograph: you only receive text. Avoid body judgements, medical advice, product prices and invented shopping links. Do not claim to be a human or to contact other people. The selected style and occasion are preferences, not mandatory instructions.
            """
            let session = LanguageModelSession(instructions: instructions)
            let context = history.suffix(8).map { ($0.outgoing ? "User: " : "Stylist: ") + String($0.text.prefix(600)) }.joined(separator: "\n")
            let prompt = "Preferred style: \(style). Occasion: \(occasion).\nPrevious conversation:\n\(context)\nUser's latest question: \(message)"
            do {
                let response = try await session.respond(to: prompt)
                try Task.checkCancellation()
                if !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return StylistReply(text: response.content, source: "On-device AI")
                }
            } catch {
                try Task.checkCancellation()
                // A curated guide remains available when the device model cannot answer.
            }
        }
        #endif
        return StylistReply(text: StylistGuides.reply(to: message, style: style, occasion: occasion, history: history), source: "Style guide")
    }
}

private enum StylistGuides {
    struct Topic {
        let keys: [String]
        let answers: [String]
        let chinese: String
    }
    static let topics: [Topic] = [
        Topic(keys: ["shirt", "衬衫"], answers: [
            "Start with a white shirt and straight-leg trousers. Leave the collar open, roll the cuffs once and choose loafers or clean sneakers. A tan belt adds a warm accent without making the outfit busy.",
            "Try your shirt open over a simple tank or tee, with relaxed denim. Keep the base in one color family, then add a structured bag. For a sharper version, button the shirt and tuck only the front."
        ], chinese: "白衬衫可以配直筒长裤，领口自然敞开、袖口卷一道，再选乐福鞋或简洁运动鞋。想更休闲，可以把衬衫当外搭，内搭素色上衣和牛仔裤。"),
        Topic(keys: ["color", "colour", "颜色", "配色"], answers: [
            "Choose two quiet colors and one accent: cream + charcoal + burgundy is an easy starting point. Repeat the accent in one small detail, such as a bag or scarf, and keep the shoes neutral.",
            "For a softer palette, combine navy with oat or pale blue with chocolate. Keep the largest pieces simple; mixing a knit with smooth cotton adds interest without needing another color."
        ], chinese: "先用两个基础色加一个点缀色，例如奶油白、炭灰与酒红。让点缀色出现在包或围巾上，鞋子保持中性。海军蓝配燕麦色、浅蓝配巧克力色也很容易组合。"),
        Topic(keys: ["shoe", "sneaker", "heel", "鞋"], answers: [
            "Let the trouser hem guide the shoe. A straight or cropped hem works with loafers or low-profile sneakers; a wider hem needs enough shoe showing so it doesn't pool on the ground. Comfort comes first.",
            "Try switching just the shoes before changing the whole look: clean sneakers make tailoring relaxed, while loafers sharpen denim. Repeat a shoe color elsewhere in the outfit for a connected finish."
        ], chinese: "先看裤脚长度再选鞋：直筒或九分裤适合乐福鞋、低帮运动鞋；阔腿裤要避免裤脚拖地。可以只换鞋试试，同一套牛仔装搭乐福鞋更利落，搭运动鞋更轻松。"),
        Topic(keys: ["jean", "denim", "牛仔"], answers: [
            "Pair straight-leg denim with a fine knit and a lightweight jacket. Keep one half of the silhouette more structured. A simple belt and loafers can make the same jeans feel ready for dinner.",
            "A denim-on-denim look is easier when the washes are clearly different. Try a light shirt with darker jeans, then break them up with a white tee. Use one understated accessory rather than several statement pieces."
        ], chinese: "直筒牛仔裤可以搭细针织和轻外套，一件松、一件利落会更有层次。牛仔叠穿时可以选明显不同的深浅色，中间用白色上衣过渡。"),
        Topic(keys: ["layer", "jacket", "coat", "叠穿", "外套"], answers: [
            "Build from thin to thick: tee, open shirt, then a jacket. Let a little of the middle layer show at the collar or hem. Keep two of the layers close in color so the silhouette stays intentional.",
            "For a lighter layered outfit, try a fine knit over your shoulders with a shirt and straight trousers. Alternatively, an open jacket over a single-color base gives definition without extra bulk."
        ], chinese: "叠穿从薄到厚：素色上衣、敞开的衬衫、外套。领口或下摆露出少量中间层即可，其中两层用相近颜色，会更整齐。轻薄针织披肩也是不厚重的选择。"),
        Topic(keys: ["work", "office", "interview", "上班", "通勤", "面试"], answers: [
            "Try a soft blazer, plain top and straight trousers. Choose shoes you can comfortably walk in and keep accessories simple. Check the workplace dress code before adding denim or very casual footwear.",
            "A matching neutral top and trouser base makes weekday dressing easy. Add a textured cardigan or relaxed jacket, then one polished detail—a belt, watch or structured bag."
        ], chinese: "通勤可以用柔软西装、素色上衣和直筒裤组合，鞋子以方便走路为先。也可以用同色系上下装搭开衫，再用腰带、手表或挺括的包增加精致感；先考虑工作场合的着装要求。"),
        Topic(keys: ["travel", "airport", "trip", "旅行", "出游"], answers: [
            "Build a travel outfit around soft trousers, a breathable tee and a removable layer. Wear shoes you've already broken in. Choose two base colors so the same pieces can be mixed through the trip.",
            "For a small travel wardrobe, pack one light outer layer, two tops and a versatile bottom in compatible tones. A crossbody bag keeps essentials close; a scarf adds variety without taking much space."
        ], chinese: "旅行搭配优先选柔软长裤、透气上衣和方便穿脱的外套，鞋子用已经穿习惯的款式。行李围绕两个基础色准备，轻薄围巾能增加变化，斜挎包也方便拿取物品。"),
        Topic(keys: ["date", "dinner", "party", "约会", "聚会", "晚餐"], answers: [
            "Start with a piece you already feel good wearing, then add one elevated texture: a satin shirt, suede jacket or fine knit. Keep the rest simple and choose footwear that suits the venue.",
            "Try a dark tonal base with one softer accent, such as a cream shirt or textured jacket. A small accessory can be the focal point; you don't need every piece to stand out."
        ], chinese: "约会或晚餐先选你穿着自在的一件单品，再增加一种细腻质感，例如缎面衬衫、绒面外套或细针织。其余保持简洁，鞋子按场地来选，不需要每件都抢眼。"),
        Topic(keys: ["summer", "hot", "夏", "炎热"], answers: [
            "Choose airy cotton or linen with a relaxed cut. An open shirt over a simple base gives coverage and flexibility. Light tones can feel fresh; keep a light layer for cool indoor spaces.",
            "Try a breathable shirt with easy shorts or loose trousers. Add comfortable sandals or canvas shoes, then keep jewelry minimal. A hat can finish the outfit without another heavy layer."
        ], chinese: "夏天可以选宽松棉麻上衣配短裤或轻薄长裤。敞开的衬衫方便增减，鞋子选舒适凉鞋或帆布鞋，室内空调较冷时带一件薄外套。"),
        Topic(keys: ["winter", "cold", "冬", "冷"], answers: [
            "Use a comfortable base layer, a knit and a coat with room through the shoulders. Keep socks and footwear suited to the weather. A scarf in a neighboring color creates a softer finish.",
            "Try a tonal knit-and-trouser base under a contrasting coat. Mix smooth wool with a ribbed scarf for texture, and check that your outer layer closes comfortably over everything."
        ], chinese: "冷天用贴身打底、针织和肩部有余量的外套分层，鞋袜也要适合天气。外套里面用同色系，再用罗纹围巾增加质感，确认外套叠穿后仍能舒适扣上。"),
        Topic(keys: ["accessor", "bag", "belt", "jewel", "配饰", "包包", "腰带"], answers: [
            "Pick one focal accessory and let the others support it. A structured bag pairs well with relaxed clothes; a soft bag relaxes tailoring. Echo one color from the outfit instead of matching every item.",
            "Try a narrow belt, a simple watch or a small necklace—one is enough to start. Check the look without accessories first, then add only the detail that improves the balance."
        ], chinese: "先选一个重点配饰，其余做陪衬。挺括的包能让休闲装更利落，柔软的包能中和西装感。不必每件都同色，呼应衣服里的一种颜色即可。"),
        Topic(keys: ["budget", "buy", "shop", "便宜", "预算", "购买"], answers: [
            "Start by remixing what you own: change the tuck, roll the cuffs or swap shoes. Before buying anything, identify one gap that would work with at least three existing outfits. No new purchase is necessary for a fresh combination.",
            "Make a short wardrobe list before shopping: tops, bottoms, layers and shoes. Look for a missing connection between pieces you already wear. Fit, comfort and care requirements matter more than a trend label."
        ], chinese: "先试试改变塞衣角、卷袖口或换鞋，不一定要买新衣。购买前找出衣橱里真正缺少、而且能与至少三套衣服组合的单品，优先看合身、舒适和打理要求。"),
        Topic(keys: ["men", "male", "男装", "男生", "男性"], answers: [
            "For a menswear direction, try an open-collar shirt, relaxed straight trousers and low-profile shoes. Keep the shoulder fit comfortable and let one piece carry texture. These proportions can be adapted to any wardrobe.",
            "A plain tee, pleated trousers and a short jacket make a versatile starting point. Keep the tee hem around the trouser rise, then use a belt or clean shoe shape to sharpen the finish."
        ], chinese: "偏男装方向可以试敞领衬衫、直筒长裤和低帮鞋，肩部合身舒适，让其中一件有质感变化。素色T恤、打褶长裤与短外套也适合日常；这些搭配比例不限性别。"),
        Topic(keys: ["dress", "skirt", "裙"], answers: [
            "Balance a fluid skirt or dress with a short jacket or neat cardigan. Choose shoes for the day's walking first. If the print is busy, take one color from it for a plain outer layer.",
            "Try a simple skirt with a relaxed shirt, or a plain dress under an open knit. Keep one area defined—the waist, cuffs or jacket length—so the layers don't compete."
        ], chinese: "飘逸的裙装可以配短外套或简洁开衫。花纹较多时，从图案中挑一种颜色做纯色外搭。腰线、袖口或外套长度保持一处明确，层次会更舒服。")
    ]
    static let formulas: [String: String] = [
        "Minimalist": "A clean tee + straight trousers + simple sneakers. Keep the palette to cream, charcoal and one warm neutral.",
        "Streetwear": "A relaxed tee + wide denim + a short jacket. Let the silhouette do the work and keep accessories focused.",
        "Vintage": "A textured shirt + straight denim + a characterful jacket. Choose one retro reference and balance it with simple modern basics.",
        "Soft Tailoring": "A fluid shirt + pleated trousers + loafers. Soften the structure with an open collar and a relaxed sleeve.",
        "Smart Casual": "An airy shirt + tailored trousers + low-profile shoes. Mix one relaxed piece with one polished piece.",
        "Cozy": "A soft knit + relaxed trousers + comfortable flats or sneakers. Mix textures within one color family.",
        "City Chic": "A statement coat + a plain base + a structured bag. Let the outer layer lead the outfit.",
        "Weekend": "An open shirt + a simple tee + easy denim. Finish with shoes you can walk in all day."
    ]
    static func reply(to message: String, style: String, occasion: String, history: [ConversationMessage]) -> String {
        let q = message.lowercased()
        let chinese = message.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        let previous = history.filter { !$0.outgoing }.map(\.text)
        func topic(for query: String) -> Topic? {
            topics.first { topic in topic.keys.contains { key in
                if key.unicodeScalars.contains(where: { $0.value > 127 }) { return query.contains(key) }
                return query.split(whereSeparator: { !$0.isLetter }).contains { $0.hasPrefix(key) }
            } }
        }
        var matched = topic(for: q)
        if matched == nil, ["another", "different", "more casual", "more formal", "换一个", "还有", "再来", "更休闲"].contains(where: { q.contains($0) }),
           let lastQuestion = history.last(where: { $0.outgoing })?.text.lowercased() {
            matched = topic(for: lastQuestion)
        }
        if q.contains("photo") || q.contains("picture") || q.contains("照片") || q.contains("图片") {
            return chinese ? "照片会留在你的灵感板中，这里的建议不会读取照片内容。请描述衣服的颜色、款式以及准备去的场合，我可以根据文字给你搭配建议。" : "Your photo stays in your inspiration board; these suggestions don't read images. Describe the colors, pieces and occasion, and we can build a combination from your words."
        }
        if let matched {
            if chinese { return matched.chinese + "\n\n你想保留哪件单品？也可以告诉我更偏休闲还是利落，我再帮你调整。" }
            let answer = matched.answers.first { candidate in !previous.contains(where: { $0.contains(candidate) }) } ?? matched.answers[previous.count % matched.answers.count]
            return answer + "\n\nFor your \(occasion.lowercased()) plans, which piece would you like to keep as the starting point?"
        }
        if chinese {
            return "可以先用一件素色上衣、直筒下装与舒适鞋子做基础，再选衬衫或针织作外搭。配色控制在两到三种，留一个包或围巾作重点。\n\n你选了\(style)方向。告诉我最想搭配的衣服、颜色和场合，或者问我鞋子、牛仔裤、叠穿、通勤、旅行、配饰，我可以给更具体的建议。"
        }
        let formula = formulas[style] ?? formulas["Minimalist"]!
        let finish = ["Try one version with the top tucked and one untucked; keep the one that feels easier to move in.", "Repeat one color in two places, then leave the rest understated.", "Before adding another piece, check whether swapping shoes creates the change you want.", "Use texture for interest: cotton with knitwear, or smooth fabric with denim."][previous.count % 4]
        return "YOUR \(style.uppercased()) STARTING POINT\n\(formula)\n\nTHE FINISH\n\(finish)\n\nWhat pieces do you already have for your \(occasion.lowercased()) plans? You can ask about colors, shoes, layering or a specific garment."
    }
}

@MainActor extension AppStore {
    var stylistFreeRemaining: Int { max(0, CoinEconomy.stylistFreeReplies - (state?.stylistFreeUsed ?? 0)) }
    var stylistReplyCost: Int { stylistFreeRemaining > 0 ? 0 : CoinEconomy.stylistReplyPrice }
    @discardableResult func saveStylistReply(turnID: String, accountID: String, question: String, reply: StylistReply, approvedCost: Int) -> Bool {
        guard accountID == sessionID else { return false }
        return commit { value in
            guard !(value.stylistCompletedTurns ?? []).contains(turnID) else { return }
            let free = (value.stylistFreeUsed ?? 0) < CoinEconomy.stylistFreeReplies
            let cost = free ? 0 : CoinEconomy.stylistReplyPrice
            guard cost <= approvedCost, value.coins >= cost else { throw TutuFailure.message("Your balance or free allowance changed. Please send again; nothing was deducted.") }
            if free { value.stylistFreeUsed = (value.stylistFreeUsed ?? 0) + 1 }
            else {
                value.coins -= cost
                value.ledger.insert(WalletEntry(title: "Style consultation", amount: -cost, kind: .spending), at: 0)
            }
            value.stylist.append(ConversationMessage(text: question, outgoing: true, status: "Complete"))
            value.stylist.append(ConversationMessage(text: reply.text, outgoing: false, status: "Complete", replySource: reply.source))
            var completed = value.stylistCompletedTurns ?? []; completed.insert(turnID); value.stylistCompletedTurns = completed
            value.drafts["stylist"] = nil
        }
    }
}
