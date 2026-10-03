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
    const publishButton = document.getElementById("publish-paper");
    const notice = document.getElementById("site-notice");
    let user = null;

    accountbar.style.display = "flex";
    publishButton.hidden = false;
    notice.textContent = "公開投稿は誰でも読めます。投稿するにはメールでログインしてください。下書きはこの端末だけに保存されます。";
    document.getElementById("save-help").textContent = "下書きはこの端末だけに保存されます。公開投稿にはログインが必要です。";
    liveMode = true;
    grid.replaceChildren(el("div", "loading", "公開投稿を読み込んでいます…"));

    function updateAccount(nextUser) {
      user = nextUser;
      accountName.textContent = user?.email || "";
      accountButton.textContent = user ? "ログアウト" : "ログイン";
      document.getElementById("profile-button").hidden = !user;
      document.getElementById("notices-button").hidden = !user;
      render();
      window.dispatchEvent(new CustomEvent("bonbon:authchange", { detail: { user } }));
    }

    accountButton.addEventListener("click", async () => {
      if (!user) { accountDialog.showModal(); return; }
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

    window.bonbonCardActions = (paper, foot) => {
      const actions = el("div", "social-actions");
      const own = user?.id === paper.user_id;
      const mayDelete = own || window.bonbonIsModerator?.();
      const button = el("button", `social-action${mayDelete ? " dangerbutton" : ""}`, mayDelete ? "削除" : "通報");
      button.type = "button";
      button.addEventListener("click", () => mayDelete ? deletePaper(paper) : reportPaper(paper));
      actions.append(button);
      foot.append(actions);
    };

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
      if (!user) {
        if (!saveDraft(paper)) return;
        clearComposer();
        filter = "自分の下書き";
        window.bonbonSelectFeed?.("new");
        document.querySelectorAll("[data-filter]").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.filter === filter)));
        render();
        accountDialog.showModal();
        showToast("下書きに保存しました。ログイン後に編集して公開できます");
        return;
      }
      publishButton.disabled = true;
      publishButton.textContent = "公開しています…";
      const uploaded = [];
      let stage = "投稿";
      try {
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
      if (!user || paper.user_id !== user.id && !window.bonbonIsModerator?.()) return;
      if (!confirm("この公開投稿を削除しますか？")) return;
      const { error } = await client.from("papers").delete().eq("id", paper.id);
      if (error) { showToast("削除できませんでした"); return; }
      const paths = (paper.blocks || []).filter(b => b.type === "image" && b.path).map(b => b.path);
      if (paths.length && paper.user_id === user.id) await client.storage.from("paper-images").remove(paths);
      await loadPapers();
      showToast("公開投稿を削除しました");
    }

    async function reportPaper(paper) {
      if (!user) { accountDialog.showModal(); showToast("通報するにはログインしてください"); return; }
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
    window.dispatchEvent(new CustomEvent("bonbon:ready", { detail: { client } }));
    loadPapers();
  }
})();
