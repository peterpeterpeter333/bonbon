import SwiftUI
import WebKit

struct RootView: View {
    @StateObject private var store = PaperStore()
    @AppStorage("savedPaperIDs") private var savedPaperIDs = ""
    @AppStorage("readerTextSize") private var readerTextSize = 18.0
    @State private var query = ""
    @State private var selection = 0

    private var savedIDs: Set<String> { Set(savedPaperIDs.split(separator: ",").map(String.init)) }

    private var visiblePapers: [Paper] {
        guard !query.isEmpty else { return store.papers }
        return store.papers.filter { paper in
            [paper.title, paper.author ?? "", paper.category ?? "", paper.summary, (paper.tags ?? []).joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                Group {
                    if store.isLoading && store.papers.isEmpty {
                        ProgressView("投稿を読み込み中")
                    } else if let error = store.errorMessage, store.papers.isEmpty {
                        ContentUnavailableView(error, systemImage: "wifi.exclamationmark")
                    } else {
                        List(visiblePapers) { paper in
                            NavigationLink(value: paper) {
                                PaperRow(paper: paper, isSaved: savedIDs.contains(paper.id.uuidString))
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await store.refresh() }
                    }
                }
                .navigationTitle("論文もどき")
                .searchable(text: $query, prompt: "タイトル・本文・タグを検索")
                .toolbar { Button("更新", systemImage: "arrow.clockwise") { Task { await store.refresh() } } }
                .navigationDestination(for: Paper.self) { paper in
                    PaperDetail(paper: paper, textSize: $readerTextSize, isSaved: savedIDs.contains(paper.id.uuidString)) {
                        var ids = savedIDs
                        let id = paper.id.uuidString
                        if !ids.insert(id).inserted { ids.remove(id) }
                        savedPaperIDs = ids.sorted().joined(separator: ",")
                    }
                }
            }
            .tabItem { Label("読む", systemImage: "text.book.closed") }
            .tag(0)

            NavigationStack {
                CommunityWebView()
                    .navigationTitle("投稿・交流")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("投稿・交流", systemImage: "square.and.pencil") }
            .tag(1)

            NavigationStack {
                List {
                    Section("保存した論文") {
                        ForEach(store.papers.filter { savedIDs.contains($0.id.uuidString) }) { paper in
                            NavigationLink(value: paper) { Text(paper.title) }
                        }
                        if savedIDs.isEmpty { Text("まだ保存した論文はありません").foregroundStyle(.secondary) }
                    }
                    Section("このアプリについて") {
                        Link("コミュニティガイドライン", destination: BonbonConfig.site.appending(path: "community-guidelines.html"))
                        Link("利用規約", destination: BonbonConfig.site.appending(path: "terms.html"))
                        Link("プライバシーポリシー", destination: BonbonConfig.site.appending(path: "privacy.html"))
                        Link("お問い合わせ", destination: URL(string: "mailto:darth_vader_0923@outlook.jp")!)
                        Text("退会・投稿の削除は「投稿・交流」タブのアカウントから行えます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("マイページ")
                .navigationDestination(for: Paper.self) { paper in
                    PaperDetail(paper: paper, textSize: $readerTextSize, isSaved: true) {
                        var ids = savedIDs
                        ids.remove(paper.id.uuidString)
                        savedPaperIDs = ids.sorted().joined(separator: ",")
                    }
                }
            }
            .tabItem { Label("マイページ", systemImage: "person.crop.circle") }
            .tag(2)
        }
        .tint(Color(red: 0.13, green: 0.31, blue: 0.26))
        .task { await store.refresh() }
    }
}

private struct PaperRow: View {
    let paper: Paper
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(paper.category ?? "論文もどき").font(.caption).foregroundStyle(.secondary)
            Text(paper.title).font(.headline).foregroundStyle(.primary)
            Text(paper.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            HStack {
                Text(paper.author ?? "ゲスト研究者")
                Spacer()
                if isSaved { Image(systemName: "bookmark.fill") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct PaperDetail: View {
    let paper: Paper
    @Binding var textSize: Double
    let isSaved: Bool
    let toggleSaved: () -> Void
    @State private var showCommunity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(paper.category ?? "論文もどき")
                    .font(.caption).foregroundStyle(.secondary)
                Text(paper.title).font(.largeTitle.bold())
                Text("\(paper.author ?? "ゲスト研究者") ・ \(paper.created_at.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array((paper.blocks ?? []).enumerated()), id: \.offset) { _, block in
                    if block.type == "image", let url = block.imageURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                        } placeholder: { ProgressView() }
                        if let caption = block.caption, !caption.isEmpty {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if let heading = block.heading, !heading.isEmpty {
                                Text(heading).font(.title3.bold())
                            }
                            if let body = block.body, !body.isEmpty {
                                Text(body).font(.system(size: textSize)).textSelection(.enabled)
                            }
                        }
                    }
                }
                Stepper("文字サイズ \(Int(textSize))", value: $textSize, in: 14...26, step: 2)
                    .font(.footnote)
                Button("この論文にコメント・通報する") { showCommunity = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { toggleSaved() } label: { Image(systemName: isSaved ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel(isSaved ? "保存を解除" : "保存")
            ShareLink(item: paper.pageURL) { Image(systemName: "square.and.arrow.up") }
        }
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
