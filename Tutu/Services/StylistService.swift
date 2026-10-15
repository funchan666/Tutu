import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct StylistReply {
    let text: String
    let source: String
}
struct StyleDirection: Decodable, Identifiable {
    let name: String
    let image: String
    let detail: String
    var id: String { name }
    static var all: [StyleDirection] { Catalog.snapshot?.settings.styles ?? [] }
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
            }
        }
        #endif
        return StylistReply(text: StylistGuides.reply(to: message, style: style, occasion: occasion, history: history), source: "Style guide")
    }
}

enum StylistGuides {
    struct Topic: Decodable {
        let keys: [String]
        let answers: [String]
        let chinese: String
    }
    static var topics: [Topic] { Catalog.snapshot?.settings.topics ?? [] }
    static var formulas: [String: String] { Catalog.snapshot?.settings.formulas ?? [:] }
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
        let formula = formulas[style] ?? formulas["Minimalist"] ?? "Please describe the pieces you would like to style."
        let finishes = Catalog.snapshot?.settings.finishes ?? []
        let finish = finishes.isEmpty ? "" : finishes[previous.count % finishes.count]
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
