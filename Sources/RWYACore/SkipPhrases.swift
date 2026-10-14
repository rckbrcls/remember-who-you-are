import Foundation

public enum SkipPhrases {
    public static let regular = [
        "I choose ignorance. 💀",
        "Skill issue. Whatever. 🤡",
        "Let the AI cook. 🤖",
        "Thinking is overrated. 🧠",
        "I'm just a prompt engineer. ✨",
    ]
    public static let streak = "AI should get your degree. 💀"
    public static let streakThreshold = 3

    /// Phrase for the skip button; escalates once the user keeps skipping.
    public static func phrase(forSkipCount count: Int) -> String {
        if count >= streakThreshold { return streak }
        return regular[count % regular.count]
    }
}
