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
                            Button("アカウント管理", systemImage: "gearshape") {
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
        .tint(Color(red: 19 / 255, green: 36 / 255, blue: 61 / 255))
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

    func makeUIView(context: Context) -> WKWebView {
        webView.uiDelegate = context.coordinator
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKUIDelegate {
        private func present(_ alert: UIAlertController) -> Bool {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow),
                let root = window.rootViewController else { return false }
            var controller = root
            while let next = controller.presentedViewController { controller = next }
            controller.present(alert, animated: true)
            return true
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "論文もどき", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            if !present(alert) { completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "確認", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            if !present(alert) { completionHandler(false) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: "入力", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            if !present(alert) { completionHandler(nil) }
        }
    }
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
