import SwiftUI
import WebKit

struct RootView: View {
    @StateObject private var browser = BonbonBrowser()
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
            BonbonWebView(webView: browser.webView)
                .navigationTitle("論文もどき")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("再読み込み", systemImage: "arrow.clockwise") {
                            browser.webView.reload()
                        }
                        ShareLink(item: BonbonConfig.site) {
                            Label("共有", systemImage: "square.and.arrow.up")
                        }
                        Button("アプリ情報", systemImage: "ellipsis.circle") {
                            showingInfo = true
                        }
                    }
                }
                .sheet(isPresented: $showingInfo) { AppInfoView() }
        }
        .tint(Color(red: 19 / 255, green: 36 / 255, blue: 61 / 255))
    }
}

@MainActor
private final class BonbonBrowser: ObservableObject {
    let webView = WKWebView()

    init() {
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: BonbonConfig.site))
    }
}

private struct BonbonWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct AppInfoView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("このアプリについて") {
                    Link("投稿ガイドライン", destination: BonbonConfig.site.appending(path: "community-guidelines.html"))
                    Link("利用規約", destination: BonbonConfig.site.appending(path: "terms.html"))
                    Link("プライバシーポリシー", destination: BonbonConfig.site.appending(path: "privacy.html"))
                    Link("お問い合わせ", destination: URL(string: "mailto:darth_vader_0923@outlook.jp")!)
                }
                Section {
                    Text("プロフィール、保存した論文、退会はサイト内のアカウントから操作できます。")
                }
            }
            .navigationTitle("アプリ情報")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
