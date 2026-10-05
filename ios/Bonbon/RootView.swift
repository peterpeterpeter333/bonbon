import SwiftUI
import WebKit

struct RootView: View {
    @StateObject private var homeBrowser = BonbonBrowser(url: BonbonConfig.site)
    @StateObject private var profileBrowser = BonbonBrowser(url: BonbonConfig.profile)
    @State private var showingInfo = false
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                BonbonWebView(webView: homeBrowser.webView)
                    .navigationTitle("投稿・交流")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button("再読み込み", systemImage: "arrow.clockwise") {
                                homeBrowser.webView.reload()
                            }
                            ShareLink(item: BonbonConfig.site) {
                                Label("共有", systemImage: "square.and.arrow.up")
                            }
                            Button("アプリ情報", systemImage: "ellipsis.circle") {
                                showingInfo = true
                            }
                        }
                    }
            }
            .tabItem { Label("投稿・交流", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                BonbonWebView(webView: profileBrowser.webView)
                    .navigationTitle("マイページ")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button("アカウント管理", systemImage: "person.crop.circle.badge.gearshape") {
                                profileBrowser.webView.evaluateJavaScript("document.getElementById('account-button')?.click()")
                            }
                            Button("アプリ情報", systemImage: "ellipsis.circle") {
                                showingInfo = true
                            }
                        }
                    }
            }
            .tabItem { Label("マイページ", systemImage: "person.crop.circle.fill") }
            .tag(1)
        }
        .onChange(of: selection) { _, value in
            if value == 1 {
                profileBrowser.webView.reload()
            }
        }
        .sheet(isPresented: $showingInfo) { AppInfoView() }
        .tint(Color(red: 217 / 255, green: 251 / 255, blue: 104 / 255))
        .toolbarBackground(Color(red: 19 / 255, green: 36 / 255, blue: 61 / 255), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

@MainActor
private final class BonbonBrowser: ObservableObject {
    let webView = WKWebView()

    init(url: URL) {
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
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
