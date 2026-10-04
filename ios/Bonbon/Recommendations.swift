import Foundation

struct PaperSuggestion: Identifiable {
    let paper: Paper
    let reason: String
    let score: Double

    var id: UUID { paper.id }
}

enum Recommendations {
    static func related(to current: Paper, among papers: [Paper], limit: Int = 4) -> [PaperSuggestion] {
        let currentTags = Set((current.tags ?? []).map(normalize))
        let ranked = papers.filter { $0.id != current.id }.map { candidate -> PaperSuggestion in
            let sharedTags = currentTags.intersection((candidate.tags ?? []).map(normalize))
            let sameCategory = normalize(current.category ?? "") == normalize(candidate.category ?? "")
                && !(current.category ?? "").isEmpty
            let titleSimilarity = bigramSimilarity(current.title, candidate.title)
            let score = Double(sharedTags.count) * 5
                + (sameCategory ? 2.5 : 0)
                + titleSimilarity * 3
                + freshness(candidate) * 0.5
            let reason: String
            if let tag = sharedTags.sorted().first {
                reason = "共通のタグ · \(tag)"
            } else if sameCategory {
                reason = "同じカテゴリー"
            } else if titleSimilarity > 0.12 {
                reason = "近いテーマ"
            } else {
                reason = "次に読むなら"
            }
            return PaperSuggestion(paper: candidate, reason: reason, score: score)
        }
        return diversify(ranked, limit: limit)
    }

    static func forYou(_ papers: [Paper], savedIDs: Set<String>, recentIDs: [String]) -> [Paper] {
        let interests = papers.filter {
            savedIDs.contains($0.id.uuidString) || recentIDs.prefix(5).contains($0.id.uuidString)
        }
        let savedWeight = Dictionary(grouping: interests.flatMap { $0.tags ?? [] }.map(normalize), by: { $0 })
            .mapValues { Double($0.count) }
        let categories = Dictionary(grouping: interests.compactMap { $0.category }.map(normalize), by: { $0 })
            .mapValues { Double($0.count) }
        let ranked = papers.map { paper -> PaperSuggestion in
            let tagScore = (paper.tags ?? []).map { savedWeight[normalize($0)] ?? 0 }.reduce(0, +) * 2.5
            let categoryScore = (categories[normalize(paper.category ?? "")] ?? 0) * 1.5
            let score = tagScore + categoryScore + freshness(paper) * 2
            return PaperSuggestion(paper: paper, reason: "", score: score)
        }
        return diversify(ranked, limit: papers.count).map(\.paper)
    }

    private static func diversify(_ suggestions: [PaperSuggestion], limit: Int) -> [PaperSuggestion] {
        var remaining = suggestions
        var selected: [PaperSuggestion] = []
        while !remaining.isEmpty && selected.count < limit {
            let bestIndex = remaining.indices.max { lhs, rhs in
                adjusted(remaining[lhs], after: selected) < adjusted(remaining[rhs], after: selected)
            }!
            selected.append(remaining.remove(at: bestIndex))
        }
        return selected
    }

    private static func adjusted(_ item: PaperSuggestion, after selected: [PaperSuggestion]) -> Double {
        let sameCategoryCount = selected.filter { $0.paper.category == item.paper.category }.count
        return item.score - Double(sameCategoryCount) * 0.6
    }

    private static func freshness(_ paper: Paper) -> Double {
        let days = max(0, Date().timeIntervalSince(paper.created_at) / 86_400)
        return 1 / (1 + days / 14)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func bigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        func grams(_ value: String) -> Set<String> {
            let chars = Array(normalize(value).filter { !$0.isWhitespace })
            guard chars.count > 1 else { return [] }
            return Set((0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) })
        }
        let a = grams(lhs), b = grams(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}
