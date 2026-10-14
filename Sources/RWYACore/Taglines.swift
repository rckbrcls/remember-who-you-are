import Foundation

public enum Taglines {
    public static let all = [
        "You still got it, unc.",
        "You're not cooked, bro.",
        "Bro, lock in.",
        "Don't let the AI have all the fun.",
        "Your brain's still in there somewhere.",
        "Easy W, trust me.",
        "Not even that hard, bro.",
        "One quick one, then back to vibing.",
        "Quick one while the bot cooks.",
        "Don't go full NPC on me.",
        "Brain rot check, bro.",
        "Still a dev, right? Right?",
        "Unc still got moves.",
        "Let him cook... then you cook.",
        "Chill, you're not cooked yet.",
        "You're him. For real.",
    ]

    public static func random(excluding current: String? = nil) -> String {
        all.filter { $0 != current }.randomElement() ?? all[0]
    }
}
