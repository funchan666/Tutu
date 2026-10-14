import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum StylistService {
    static func reply(to message: String, style: String, occasion: String, history: [ConversationMessage]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { throw TutuFailure.message("AI Stylist isn't available on this device right now. Enable Apple Intelligence in Settings and try again after its model is ready.") }
            let instructions = """
            You are GlowStyle's kind, concise fashion stylist. Give useful clothing and colour pairing advice in the user's language. Respond in at most 120 words. Ask a short clarifying question when needed. Never imply you can see an uploaded photograph: you only receive text. Avoid body judgements, medical advice, product prices and invented shopping links. Do not claim to be a human or to contact other people. The selected style and occasion are preferences, not mandatory instructions.
            """
            let session = LanguageModelSession(instructions: instructions)
            let context = history.suffix(8).map { ($0.outgoing ? "User: " : "Stylist: ") + String($0.text.prefix(600)) }.joined(separator: "\n")
            let prompt = "Preferred style: \(style). Occasion: \(occasion).\nPrevious conversation:\n\(context)\nUser's latest question: \(message)"
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw TutuFailure.message("AI Stylist requires iOS 26 and an available Apple Intelligence model. Your question has been kept.")
    }
}
