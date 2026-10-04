(() => {
  const config = window.BONBON_CONFIG || {};
  const url = String(config.supabaseUrl || "").trim().replace(/\/$/, "");
  const key = String(config.supabasePublishableKey || "").trim();
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url) || !key) return;

  const script = document.createElement("script");
  script.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
  script.onload = start;
  script.onerror = () => showToast("公開機能の読み込みに失敗しました。再読み込みしてください");
  document.head.append(script);

  function start() {
    if (!window.supabase?.createClient) return;
    const client = window.supabase.createClient(url, key);
    const accountbar = document.getElementById("accountbar");
    const accountButton = document.getElementById("account-button");
    const accountName = document.getElementById("account-name");
    const accountDialog = document.getElementById("account-dialog");
    const accountForm = document.getElementById("account-form");
    const guestStart = document.getElementById("guest-start");
    const guestSwitch = document.getElementById("guest-switch");
    const publishButton = document.getElementById("publish-paper");
    const notice = document.getElementById("site-notice");
    let user = null, guestPromise = null;

    accountbar.style.display = "flex";
    publishButton.hidden = false;
    notice.textContent = "公開投稿は誰でも読めます。メール登録なしでゲスト投稿できます。ゲストの投稿管理はこのブラウザのログイン情報が必要です。";
    const saveHelp = document.getElementById("save-help");
    liveMode = true;
    grid.replaceChildren(el("div", "loading", "公開投稿を読み込んでいます…"));

    function updateAccount(nextUser) {
      user = nextUser;
      accountName.textContent = user?.is_anonymous ? "ゲスト" : user?.email || "";
      accountButton.textContent = user?.is_anonymous ? "ゲスト情報" : user ? "ログアウト" : "ゲストで始める";
      guestStart.hidden = !!user;
      guestSwitch.hidden = !user?.is_anonymous;
      document.getElementById("guest-help").hidden = !user?.is_anonymous;
      document.getElementById("existing-login").hidden = !!user;
      document.getElementById("profile-button").hidden = !user;
      document.getElementById("notices-button").hidden = !user;
      saveHelp.textContent = user ? "下書きはこの端末だけに保存されます。公開すると、あなたのプロフィールから読めるようになります。" : "下書きはこの端末だけに保存されます。公開時はゲストプロフィールを作成します。";
      render();
      window.dispatchEvent(new CustomEvent("bonbon:authchange", { detail: { user } }));
    }

    async function ensureGuest() {
      if (user) return user;
      if (!guestPromise) guestPromise = client.auth.signInAnonymously().then(({ data, error }) => {
        if (error || !data.user) { showToast("ゲストを開始できませんでした。少し待って再試行してください"); return null; }
        updateAccount(data.user);
        return data.user;
      }).finally(() => { guestPromise = null; });
      return guestPromise;
    }

    guestStart.addEventListener("click", async () => {
      guestStart.disabled = true;
      const identity = await ensureGuest();
      guestStart.disabled = false;
      if (identity) { accountDialog.close(); showToast("ゲストプロフィールを作りました。プロフィールから名前を変更できます"); }
    });

    guestSwitch.addEventListener("click", async () => {
      if (!user?.is_anonymous) return;
      if (!confirm("ゲストを終了して既存のメールアカウントに切り替えますか？ このゲストの投稿やプロフィールは、このブラウザから管理できなくなります。")) return;
      const { error } = await client.auth.signOut();
      if (error) { showToast("切り替えられませんでした"); return; }
      document.getElementById("existing-login").open = true;
      showToast("既存のメールアカウントでログインしてください");
    });

    accountButton.addEventListener("click", async () => {
      if (!user || user.is_anonymous) { accountDialog.showModal(); return; }
      const { error } = await client.auth.signOut();
      if (error) showToast("ログアウトできませんでした。もう一度お試しください");
      else showToast("ログアウトしました");
    });

    accountForm.addEventListener("submit", async event => {
      event.preventDefault();
      if (!accountForm.reportValidity()) return;
      const button = accountForm.querySelector('button[type="submit"]');
      button.disabled = true;
      const email = document.getElementById("account-email").value.trim();
      const { error } = await client.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: location.origin + location.pathname }
      });
      button.disabled = false;
      if (error) showToast("メールを送れませんでした。時間をおいて再試行してください");
      else {
        document.getElementById("account-help").textContent = "メールが届いたら、リンクを押してこのサイトへ戻ってください。";
        showToast("ログインリンクを送りました");
      }
    });

    client.auth.getUser().then(({ data, error }) => {
      if (!error) updateAccount(data.user);
    });
    client.auth.onAuthStateChange((_event, session) => updateAccount(session?.user || null));

    window.bonbonImageUrl = path => {
      if (typeof path !== "string" || !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg$/i.test(path)) return "";
      return client.storage.from("paper-images").getPublicUrl(path).data.publicUrl;
    };

    function moderationActions(paper, className = "moderation-actions") {
      const actions = el("div", className);
      const own = user?.id === paper.user_id;
      const mayDelete = own || window.bonbonIsModerator?.();
      if (!own) {
        const report = el("button", "social-action", "通報");
        report.type = "button";
        report.addEventListener("click", () => reportPaper(paper));
        actions.append(report);
      }
      if (mayDelete) {
        const remove = el("button", "social-action dangerbutton", "削除");
        remove.type = "button";
        remove.addEventListener("click", () => deletePaper(paper));
        actions.append(remove);
      }
      return actions;
    }

    window.bonbonCardActions = (paper, foot) => foot.append(moderationActions(paper));
    window.bonbonReadModerationActions = (paper, content) =>
      content.append(moderationActions(paper, "read-actions moderation-actions"));

    async function loadPapers() {
      const { data, error } = await client.from("papers")
        .select("id,user_id,sample_author_id,author,category,title,blocks,tags,source_paper_id,source_kind,created_at")
        .order("created_at", { ascending: false }).limit(200);
      if (error) {
        notice.textContent = "公開投稿を読み込めませんでした。設定または通信状態を確認してください。";
        publicPapers = [];
        render();
        return;
      }
      publicPapers = (data || []).map(p => ({ ...p, user_id: p.user_id || p.sample_author_id,
        sample: !!p.sample_author_id, remote: true }));
      render();
    }

    publishButton.addEventListener("click", async () => {
      const paper = collectPaper();
      if (!paper) return;
      if (!user && !await ensureGuest()) return;
      publishButton.disabled = true;
      publishButton.textContent = "公開しています…";
      const uploaded = [];
      let stage = "投稿";
      try {
        if (!form.elements.author.value.trim()) {
          const { data: profile } = await client.from("profiles").select("display_name").eq("user_id", user.id).maybeSingle();
          paper.author = (profile?.display_name || "ゲスト研究者").slice(0, 24);
        }
        const blocks = [];
        for (const block of paper.blocks) {
          if (block.type !== "image") { blocks.push(block); continue; }
          stage = "画像";
          const imagePath = `${user.id}/${crypto.randomUUID()}.jpg`;
          const blob = await (await fetch(block.src)).blob();
          const { error } = await client.storage.from("paper-images")
            .upload(imagePath, blob, { contentType: "image/jpeg", upsert: false });
          if (error) throw error;
          uploaded.push(imagePath);
          blocks.push({ type: "image", path: imagePath, caption: block.caption || "" });
        }
        stage = "投稿";
        const { error } = await client.from("papers").insert({
          user_id: user.id, author: paper.author, category: paper.category,
          title: paper.title, blocks, tags: paper.tags,
          source_paper_id: paper.source_paper_id, source_kind: paper.source_kind
        });
        if (error) throw error;
        if (draftBeingEditedId) {
          const next = drafts.filter(d => d.id !== draftBeingEditedId);
          try { localStorage.setItem(storageKey, JSON.stringify(next)); drafts = next; }
          catch { /* 公開は完了しているため、下書きは端末に残す */ }
        }
        clearComposer();
        filter = "すべて";
        document.querySelectorAll("[data-filter]").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.filter === filter)));
        await loadPapers();
        document.getElementById("papers").scrollIntoView({ behavior: "smooth" });
        showToast("論文を公開しました");
      } catch (error) {
        if (uploaded.length) await client.storage.from("paper-images").remove(uploaded);
        showToast(`${stage}の保存に失敗しました。内容は残っています。もう一度お試しください`);
        console.error("Publish failed", error);
      } finally {
        publishButton.disabled = false;
        publishButton.textContent = "公開する";
      }
    });

    async function deletePaper(paper) {
      if (!user || paper.user_id !== user.id && !window.bonbonIsModerator?.()) return false;
      if (!confirm("この公開投稿を削除しますか？ この操作は取り消せません。")) return false;
      const { error } = await client.from("papers").delete().eq("id", paper.id);
      if (error) { showToast("削除できませんでした"); return false; }
      const paths = (paper.blocks || []).filter(b => b.type === "image" && b.path).map(b => b.path);
      let imageError = null;
      if (paths.length) {
        ({ error: imageError } = await client.storage.from("paper-images").remove(paths));
      }
      await loadPapers();
      showToast(imageError ? "投稿は削除しましたが、画像の削除に失敗しました。運営者が確認してください" : "公開投稿を削除しました");
      return true;
    }

    async function reportPaper(paper) {
      if (!user) { accountDialog.showModal(); showToast("通報するにはゲストプロフィールを作ってください"); return; }
      const reason = prompt("通報理由を入力してください（500字以内）");
      if (reason === null) return;
      const text = reason.trim();
      if (!text || text.length > 500) { showToast("通報理由を1〜500字で入力してください"); return; }
      const { error } = await client.from("paper_reports")
        .insert({ paper_id: paper.id, reporter_id: user.id, reason: text });
      showToast(error ? "通報を送れませんでした。送信済みの場合があります" : "通報を受け付けました");
    }

    window.bonbonClient = client;
    window.bonbonCurrentUser = () => user;
    window.bonbonReloadPapers = loadPapers;
    window.bonbonDeletePaper = deletePaper;
    window.dispatchEvent(new CustomEvent("bonbon:ready", { detail: { client } }));
    loadPapers();
  }
})();
