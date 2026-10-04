import Foundation

enum BonbonConfig {
    static let site = URL(string: "https://peterpeterpeter333.github.io/bonbon/")!
    static let api = URL(string: "https://tgbmnxmjinciksotyqjm.supabase.co")!
    // Public client key: the database's row-level security governs access.
    static let publicKey = "sb_publishable_MjTqIsCYtMs351weuRpEAg_hcfCwkCE"
}

struct PaperBlock: Decodable, Hashable {
    let type: String
    let heading: String?
    let body: String?
    let path: String?
    let asset: String?
    let caption: String?

    var imageURL: URL? {
        if let path, !path.isEmpty {
            return BonbonConfig.api.appending(path: "storage/v1/object/public/paper-images/\(path)")
        }
        if let asset, !asset.isEmpty {
            return BonbonConfig.site.appending(path: asset)
        }
        return nil
    }
}

struct Paper: Decodable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String?
    let category: String?
    let blocks: [PaperBlock]?
    let tags: [String]?
    let created_at: Date

    var summary: String {
        blocks?.compactMap { $0.body }.first(where: { !$0.isEmpty }) ?? "本文を読む"
    }

    var pageURL: URL {
        URL(string: "#paper=\(id.uuidString.lowercased())", relativeTo: BonbonConfig.site)!.absoluteURL
    }
}

@MainActor
final class PaperStore: ObservableObject {
    @Published private(set) var papers: [Paper] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var components = URLComponents(url: BonbonConfig.api.appending(path: "rest/v1/papers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,title,author,category,blocks,tags,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(BonbonConfig.publicKey, forHTTPHeaderField: "apikey")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let value = try decoder.singleValueContainer().decode(String.self)
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let standard = ISO8601DateFormatter()
                guard let date = fractional.date(from: value) ?? standard.date(from: value) else {
                    throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid date")
                }
                return date
            }
            papers = try decoder.decode([Paper].self, from: data)
            #if DEBUG
            print("Bonbon loaded \(papers.count) papers")
            #endif
            errorMessage = nil
        } catch {
            #if DEBUG
            print("Bonbon feed request failed: \(error)")
            #endif
            errorMessage = "投稿を読み込めませんでした。通信を確認して再試行してください。"
        }
    }
}
