# Resend Free による認証メールの設定

## 現在の状態

- bonbon の Supabase プロジェクトは Free プラン。
- Authentication → Emails → SMTP Settings の `Enable custom SMTP` はオフ。標準送信は一般の利用者向けではない。
- Resend のアカウント、送信元ドメイン、API キーはまだ接続していない。秘密のキーを GitHub、ブラウザ用 JavaScript、この文書に保存しない。

## 設定する順番

1. Resend の Free アカウントを用意する。
2. 自分で DNS を変更できる独自ドメインを Resend の Domains に追加し、画面に表示される送信用 DNS レコードを設定して認証する。GitHub Pages の `github.io` は所有者として DNS を変更できないため、送信元に使わない。
3. Resend で送信用 API キーを作成する。キーは作成者が安全に保管し、このリポジトリには入れない。
4. Supabase → Authentication → Emails → SMTP Settings でカスタム SMTP を有効にする。Host `smtp.resend.com`、Port `465`、Username `resend`、Password は Resend の API キー、Sender email は認証済みドメイン上の `no-reply@...`、Sender name は `論文もどき`。
5. Supabase → Authentication → Rate Limits で認証メールの送信上限を確認する。カスタム SMTP 設定直後の初期値は毎時30通。Resend Free の月3,000通・1日100通も超えないようにする。
6. Supabase → Authentication → URL Configuration の Site URL と Redirect URL が公開サイトを指していることを確認する。実際のメールアドレスと別端末で、メールリンクからのログインを試す。
7. Resend の送信履歴で失敗・バウンスを確認する。送信数が無料枠に近づいたら、利用者がログインできなくなる前に有料プランを検討する。

参照：[Supabase Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)、[Resend SMTP](https://resend.com/changelog/smtp-service)、[Resend 料金](https://resend.com/pricing)
