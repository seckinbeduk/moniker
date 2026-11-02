import Foundation
import FoundationModels
import MonikerCore

/// The shape of a name, filled in by guided generation.
@Generable
struct GeneratedName {
    @Guide(description: "A short, specific title: 2 to 6 words in Title Case, no date, no file extension")
    var title: String

    @Guide(description: "Up to three lowercase one-word topics", .maximumCount(3))
    var tags: [String]
}

/// Apple's on-device model, through the Foundation Models framework.
struct AppleIntelligenceNamer: NamingModel {
    /// File contents are input to describe, not to judge, so use the permissive guardrails.
    let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    func suggest(instructions: String, prompt: String) async throws -> NameIdea {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 120)
        let name = try await session.respond(to: prompt, generating: GeneratedName.self, options: options).content
        return NameIdea(title: name.title, tags: name.tags)
    }
}

enum AppleIntelligence {
    /// Why the model can't be used, or nil when it's ready.
    static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac can't run Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to let Moniker name files."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready. Try again in a few minutes."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }
}
