import SwiftUI
import WebKit

private enum BonbonStyle {
    static let navy = Color(red: 19 / 255, green: 36 / 255, blue: 61 / 255)
    static let ink = Color(red: 23 / 255, green: 38 / 255, blue: 65 / 255)
    static let muted = Color(red: 91 / 255, green: 108 / 255, blue: 130 / 255)
    static let canvas = Color(red: 243 / 255, green: 246 / 255, blue: 249 / 255)
    static let lime = Color(red: 217 / 255, green: 251 / 255, blue: 104 / 255)
    static let paleBlue = Color(red: 232 / 255, green: 239 / 255, blue: 247 / 255)
}

struct RootView: View {
    @StateObject private var store = PaperStore()
    @AppStorage("savedPaperIDs") private var savedPaperIDs = ""
    @AppStorage("recentlyReadPaperIDs") private var recentlyReadPaperIDs = ""
    @AppStorage("readerTextSize") private var readerTextSize = 18.0
    @State private var query = ""
    @State private var category = "すべて"
    @State private var recommendedFirst = false
    @State private var selection = 0

    private var savedIDs: Set<String> { Set(savedPaperIDs.split(separator: ",").map(String.init)) }
    private var recentIDs: [String] { recentlyReadPaperIDs.split(separator: ",").map(String.init) }
    private var categories: [String] {
        ["すべて"] + Set(store.papers.compactMap(\.category)).sorted()
    }
    private var visiblePapers: [Paper] {
        let ordered = recommendedFirst
            ? Recommendations.forYou(store.papers, savedIDs: savedIDs, recentIDs: recentIDs)
            : store.papers
        return ordered.filter { paper in
            (category == "すべて" || paper.category == category) &&
            (query.isEmpty || [paper.title, paper.author ?? "", paper.category ?? "", paper.summary,
                               (paper.tags ?? []).joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                feed
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Paper.self) { paper in detail(for: paper) }
            }
            .tabItem { Label("読む", systemImage: "text.book.closed.fill") }
            .tag(0)

            NavigationStack {
                CommunityWebView()
                    .navigationTitle("投稿・交流")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("投稿・交流", systemImage: "square.and.pencil") }
            .tag(1)

            NavigationStack {
                myPage
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Paper.self) { paper in detail(for: paper) }
            }
            .tabItem { Label("マイページ", systemImage: "person.crop.circle") }
            .tag(2)
        }
        .tint(BonbonStyle.lime)
        .toolbarBackground(BonbonStyle.navy, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .preferredColorScheme(.light)
        .task { await store.refresh() }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                FeedHero(count: store.papers.count) { selection = 1 }
                    .padding(.horizontal, -18)

                VStack(alignment: .leading, spacing: 8) {
                    Text("みんなの論文")
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(BonbonStyle.ink)
                    Text("日常を少し違う角度から眺めた、研究の記録。")
                        .font(.subheadline)
                        .foregroundStyle(BonbonStyle.muted)
                }
                .padding(.top, 6)

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BonbonStyle.muted)
                    TextField("タイトル・本文・タグを検索", text: $query)
                        .foregroundStyle(BonbonStyle.ink)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(BonbonStyle.muted)
                    }
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { item in
                            FilterPill(title: item, selected: category == item) { category = item }
                        }
                    }
                }
                .padding(.horizontal, -18)
                .contentMargins(.horizontal, 18)

                HStack {
                    Text("\(visiblePapers.count) 本")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BonbonStyle.muted)
                    Spacer()
                    Button("新着", systemImage: "clock", action: { recommendedFirst = false })
                        .foregroundStyle(recommendedFirst ? BonbonStyle.muted : BonbonStyle.ink)
                    Button("おすすめ", systemImage: "sparkles", action: { recommendedFirst = true })
                        .foregroundStyle(recommendedFirst ? BonbonStyle.ink : BonbonStyle.muted)
                }
                .font(.caption.weight(.bold))

                if store.isLoading && store.papers.isEmpty {
                    ProgressView("投稿を読み込み中").frame(maxWidth: .infinity).padding(50)
                } else if let error = store.errorMessage, store.papers.isEmpty {
                    EmptyCard(text: error, symbol: "wifi.exclamationmark")
                } else if visiblePapers.isEmpty {
                    EmptyCard(text: "該当する論文がありません", symbol: "doc.text.magnifyingglass")
                } else {
                    ForEach(visiblePapers) { paper in
                        NavigationLink(value: paper) { PaperCard(paper: paper, isSaved: savedIDs.contains(paper.id.uuidString)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(BonbonStyle.canvas)
        .refreshable { await store.refresh() }
    }

    private var myPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MY PAGE").font(.caption.weight(.black)).tracking(2).foregroundStyle(BonbonStyle.lime)
                    Text("マイページ").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                    Text("保存した論文と、サービスの情報。")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(26)
                .background(BonbonStyle.navy, in: RoundedRectangle(cornerRadius: 22))

                SectionHeading(title: "保存した論文", subtitle: "気になった研究を、あとでもう一度。")
                let saved = store.papers.filter { savedIDs.contains($0.id.uuidString) }
                if saved.isEmpty {
                    EmptyCard(text: "まだ保存した論文はありません", symbol: "bookmark")
                } else {
                    ForEach(saved) { paper in
                        NavigationLink(value: paper) { PaperCard(paper: paper, isSaved: true) }
                            .buttonStyle(.plain)
                    }
                }

                SectionHeading(title: "このアプリについて", subtitle: "安心して楽しむための情報。")
                VStack(spacing: 0) {
                    InfoLink(title: "投稿ガイドライン", symbol: "checkmark.shield", url: BonbonConfig.site.appending(path: "community-guidelines.html"))
                    Divider()
                    InfoLink(title: "利用規約", symbol: "doc.text", url: BonbonConfig.site.appending(path: "terms.html"))
                    Divider()
                    InfoLink(title: "プライバシーポリシー", symbol: "hand.raised", url: BonbonConfig.site.appending(path: "privacy.html"))
                    Divider()
                    InfoLink(title: "お問い合わせ", symbol: "envelope", url: URL(string: "mailto:darth_vader_0923@outlook.jp")!)
                }
                .padding(.horizontal, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                Text("退会・投稿の削除は「投稿・交流」タブのアカウントから行えます。")
                    .font(.footnote).foregroundStyle(BonbonStyle.muted)
            }
            .padding(18)
        }
        .background(BonbonStyle.canvas)
    }

    private func detail(for paper: Paper) -> some View {
        PaperDetail(
            paper: paper,
            allPapers: store.papers,
            textSize: $readerTextSize,
            isSaved: savedIDs.contains(paper.id.uuidString),
            toggleSaved: { toggleSaved(paper) }
        )
        .onAppear { markRead(paper) }
    }

    private func toggleSaved(_ paper: Paper) {
        var ids = savedIDs
        let id = paper.id.uuidString
        if !ids.insert(id).inserted { ids.remove(id) }
        savedPaperIDs = ids.sorted().joined(separator: ",")
    }

    private func markRead(_ paper: Paper) {
        let id = paper.id.uuidString
        recentlyReadPaperIDs = ([id] + recentIDs.filter { $0 != id }).prefix(20).joined(separator: ",")
    }
}

private struct FeedHero: View {
    let count: Int
    let write: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.title3.bold()).foregroundStyle(BonbonStyle.navy)
                    .frame(width: 42, height: 42)
                    .background(BonbonStyle.lime, in: RoundedRectangle(cornerRadius: 11))
                Text("論文もどき").font(.title3.weight(.black)).tracking(1).foregroundStyle(.white)
                Spacer()
                Text("\(count) 本公開中")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BonbonStyle.lime)
            }
            .padding(.bottom, 13)

            Text("日常の、まじめすぎる自由研究")
                .font(.caption.weight(.black)).tracking(1.5)
                .foregroundStyle(BonbonStyle.lime)
            Text("その疑問、\n論文にしてみよう。")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .tracking(-1)
                .lineSpacing(4)
                .foregroundStyle(.white)
            Text("小さな発見も、ちょっと大げさに。\n読んで、考えて、あなたも書いてみよう。")
                .font(.subheadline)
                .lineSpacing(5)
                .foregroundStyle(.white.opacity(0.82))
            Button(action: write) {
                Label("論文を書いてみる", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .foregroundStyle(BonbonStyle.navy)
            .background(BonbonStyle.lime, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BonbonStyle.navy)
    }
}

private struct FilterPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.bold)).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .foregroundStyle(selected ? .white : BonbonStyle.ink)
        .background(selected ? BonbonStyle.navy : .white, in: Capsule())
        .overlay(Capsule().stroke(selected ? BonbonStyle.navy : Color.black.opacity(0.08)))
    }
}

private struct PaperCard: View {
    let paper: Paper
    let isSaved: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(paper.category ?? "自由研究")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color(red: 54 / 255, green: 85 / 255, blue: 118 / 255))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(BonbonStyle.paleBlue, in: Capsule())
                Spacer()
                if isSaved { Image(systemName: "bookmark.fill").foregroundStyle(BonbonStyle.navy) }
            }
            if let imageURL = paper.blocks?.compactMap(\.imageURL).first {
                PaperImage(url: imageURL, fit: .fill)
                    .frame(height: 158)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(paper.title)
                .font(.system(size: 20, weight: .bold))
                .lineSpacing(4)
                .foregroundStyle(BonbonStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(paper.summary)
                .font(.subheadline)
                .lineSpacing(5)
                .foregroundStyle(BonbonStyle.muted)
                .lineLimit(3)
            HStack {
                Text("by \(paper.author ?? "ゲスト研究者")")
                Spacer()
                Text("論文を読む  ↗").foregroundStyle(Color(red: 36 / 255, green: 86 / 255, blue: 142 / 255))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(BonbonStyle.muted)
            .padding(.top, 12)
            .overlay(alignment: .top) { BonbonStyle.paleBlue.frame(height: 1) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.black.opacity(0.06)))
        .shadow(color: BonbonStyle.navy.opacity(0.05), radius: 12, y: 5)
    }
}

private struct PaperDetail: View {
    let paper: Paper
    let allPapers: [Paper]
    @Binding var textSize: Double
    let isSaved: Bool
    let toggleSaved: () -> Void
    @State private var showCommunity = false

    private var suggestions: [PaperSuggestion] { Recommendations.related(to: paper, among: allPapers) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(paper.category ?? "自由研究")
                            .font(.caption.weight(.heavy))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(BonbonStyle.navy)
                            .background(BonbonStyle.lime, in: Capsule())
                        Spacer()
                        Text("論文もどき / RESEARCH NOTE")
                            .font(.caption2.weight(.black)).tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(paper.title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .tracking(-1)
                        .lineSpacing(5)
                        .foregroundStyle(.white)
                    Text("\(paper.author ?? "ゲスト研究者")  ·  \(paper.created_at.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                    if let tags = paper.tags, !tags.isEmpty {
                        Text(tags.map { "#\($0)" }.joined(separator: "  "))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BonbonStyle.lime)
                    }
                }
                .padding(23)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BonbonStyle.navy, in: RoundedRectangle(cornerRadius: 20))

                ForEach(Array((paper.blocks ?? []).enumerated()), id: \.offset) { index, block in
                    if block.type == "image", let url = block.imageURL {
                        VStack(alignment: .leading, spacing: 10) {
                            PaperImage(url: url, fit: .fit)
                                .frame(maxWidth: .infinity)
                            if let caption = block.caption, !caption.isEmpty {
                                Text(caption).font(.caption).foregroundStyle(BonbonStyle.muted)
                            }
                        }
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                    } else if block.type == "text" && (block.heading != nil || block.body != nil) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let heading = block.heading, !heading.isEmpty {
                                Text(heading.uppercased())
                                    .font(.caption.weight(.black)).tracking(1.5)
                                    .foregroundStyle(Color(red: 56 / 255, green: 98 / 255, blue: 137 / 255))
                            }
                            if let body = block.body, !body.isEmpty {
                                Text(body)
                                    .font(.system(size: textSize))
                                    .lineSpacing(8)
                                    .foregroundStyle(BonbonStyle.ink)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(21)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == 0 ? Color(red: 237 / 255, green: 244 / 255, blue: 250 / 255) : .white,
                                    in: RoundedRectangle(cornerRadius: 17))
                        .overlay(alignment: .leading) {
                            if index == 0 {
                                Color(red: 66 / 255, green: 119 / 255, blue: 180 / 255)
                                    .frame(width: 4).clipShape(Capsule())
                            }
                        }
                    }
                }

                HStack {
                    Image(systemName: "textformat.size").foregroundStyle(BonbonStyle.muted)
                    Stepper("文字サイズ  \(Int(textSize))", value: $textSize, in: 14...26, step: 2)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))

                Button { showCommunity = true } label: {
                    Label("コメント・いいね・通報を見る", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .foregroundStyle(BonbonStyle.navy)
                .background(BonbonStyle.lime, in: RoundedRectangle(cornerRadius: 13))

                if !suggestions.isEmpty {
                    SectionHeading(title: "続けて読む", subtitle: "この論文に近いテーマから選びました。")
                        .padding(.top, 18)
                    ForEach(suggestions) { item in
                        NavigationLink(value: item.paper) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.reason)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(Color(red: 56 / 255, green: 98 / 255, blue: 137 / 255))
                                Text(item.paper.title)
                                    .font(.headline)
                                    .foregroundStyle(BonbonStyle.ink)
                                HStack {
                                    Text(item.paper.category ?? "自由研究")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BonbonStyle.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 18)
        }
        .background(BonbonStyle.canvas)
        .navigationTitle("論文を読む")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            Button(action: toggleSaved) { Image(systemName: isSaved ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel(isSaved ? "保存を解除" : "保存")
            ShareLink(item: paper.pageURL) { Image(systemName: "square.and.arrow.up") }
        }
        .tint(BonbonStyle.navy)
        .sheet(isPresented: $showCommunity) {
            NavigationStack {
                CommunityWebView(url: paper.pageURL)
                    .navigationTitle("論文の交流")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("閉じる") { showCommunity = false } }
            }
        }
    }
}

private struct PaperImage: View {
    let url: URL
    let fit: ContentMode
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: fit)
            case .failure:
                Label("画像を表示できません", systemImage: "photo")
                    .font(.caption).foregroundStyle(BonbonStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 130)
            default:
                ProgressView().frame(maxWidth: .infinity, minHeight: 130)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.weight(.heavy)).foregroundStyle(BonbonStyle.ink)
            Text(subtitle).font(.subheadline).foregroundStyle(BonbonStyle.muted)
        }
    }
}

private struct EmptyCard: View {
    let text: String
    let symbol: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(BonbonStyle.muted)
            Text(text).font(.subheadline).foregroundStyle(BonbonStyle.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct InfoLink: View {
    let title: String
    let symbol: String
    let url: URL
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 22)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }
            .foregroundStyle(BonbonStyle.ink)
            .padding(.vertical, 17)
        }
    }
}

private struct CommunityWebView: UIViewRepresentable {
    var url = BonbonConfig.site

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
