(() => {
  const search = document.getElementById("paper-search");
  const profileDialog = document.getElementById("profile-dialog");
  const profileContent = document.getElementById("profile-content");
  const noticesDialog = document.getElementById("notices-dialog");
  const noticesContent = document.getElementById("notices-content");
  let client, feed = "new", viewer = null, moderator = false;
  let profiles = new Map(), likeCounts = new Map(), commentCounts = new Map();
  let repostCounts = new Map(), myLikes = new Set(), myBookmarks = new Set();
  let myReposts = new Set(), following = new Set(), muted = new Set(), blocked = new Set();
  let reposts = [];

  const button = (label, action, className = "social-action") => {
    const b = el("button", className, label);
    b.type = "button";
    b.addEventListener("click", action);
    return b;
  };
  const iconPaths = {
    like: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 1 0-7.8 7.8L12 21.2l8.8-8.8a5.5 5.5 0 0 0 0-7.8Z"/>',
    comment: '<path d="M20.5 11.5a8.5 8.5 0 0 1-8.5 8.5c-1.4 0-2.8-.3-4-1l-4.5 1 1.1-4.1a8.5 8.5 0 1 1 15.9-4.4Z"/>',
    repost: '<path d="M4 7h13l-3-3m3 3-3 3M20 17H7l3-3m-3 3 3 3"/>',
    bookmark: '<path d="M6 3.5h12v17l-6-4-6 4v-17Z"/>',
    share: '<path d="M12 16V3m0 0L8 7m4-4 4 4M5 12v8h14v-8"/>'
  };
  const iconButton = (kind, label, action, { count, active = false, showLabel = false } = {}) => {
    const b = button("", action, `social-action icon-action icon-${kind}${active ? " is-active" : ""}`);
    b.setAttribute("aria-label", label);
    b.title = label;
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.setAttribute("viewBox", "0 0 24 24");
    icon.setAttribute("aria-hidden", "true");
    icon.innerHTML = iconPaths[kind];
    b.append(icon);
    if (count !== undefined) b.append(el("span", "action-count", String(count)));
    if (showLabel) b.append(el("span", "action-label", label.split(" ")[0]));
    return b;
  };
  const numberFor = (map, id) => map.get(id) || 0;
  const authorName = id => profiles.get(id)?.display_name || "研究者";
  const paperUrl = id => `${location.origin}${location.pathname}#paper=${id}`;
  const needsLogin = () => {
    if (viewer) return false;
    document.getElementById("account-dialog").showModal();
    showToast("この機能にはメールでのログインが必要です");
    return true;
  };
  const ownOrModerated = userId => viewer && (viewer.id === userId || moderator);

  window.bonbonIsModerator = () => moderator;
  window.bonbonCommunityFilter = paper => {
    if (!paper.local && (muted.has(paper.user_id) || blocked.has(paper.user_id) ||
      paper.repostActor && (muted.has(paper.repostActor) || blocked.has(paper.repostActor)))) return false;
    const q = search.value.trim().toLocaleLowerCase();
    if (q && ![paper.title, paper.author, paper.category, ...(paper.tags || [])]
      .some(value => String(value || "").toLocaleLowerCase().includes(q))) return false;
    if (paper.local) return feed === "new";
    if (feed === "bookmarks") return myBookmarks.has(paper.id);
    if (feed === "following") return following.has(paper.user_id) || following.has(paper.repostActor) ||
      reposts.some(item => item.paper_id === paper.id && following.has(item.user_id));
    return true;
  };
  window.bonbonSortPapers = papers => {
    if (feed !== "recommended") return papers;
    const liked = papers.filter(p => myLikes.has(p.id) || myBookmarks.has(p.id));
    const interests = new Set(liked.flatMap(p => [p.category, ...(p.tags || [])]));
    const score = p => {
      const ageHours = Math.max(0, (Date.now() - Date.parse(p.feedCreatedAt || p.created_at)) / 3600000);
      const interest = [p.category, ...(p.tags || [])].filter(value => interests.has(value)).length;
      return interest * 4 + (following.has(p.user_id) ? 5 : 0) +
        Math.min(numberFor(likeCounts, p.id), 20) * 0.6 +
        Math.min(numberFor(commentCounts, p.id), 20) * 0.8 +
        Math.min(numberFor(repostCounts, p.id), 20) * 0.5 + 5 / (1 + ageHours / 24);
    };
    return papers.slice().sort((a, b) => score(b) - score(a));
  };
  window.bonbonRepostFeed = () => reposts.filter(item => item.paper).map(item => ({
    ...item.paper, user_id: item.paper.user_id || item.paper.sample_author_id,
    sample: !!item.paper.sample_author_id, remote: true, repostActor: item.user_id,
    repostBy: authorName(item.user_id), repostQuote: item.quote,
    feedCreatedAt: item.created_at
  }));

  search.addEventListener("input", () => window.bonbonRender?.());
  window.bonbonSelectFeed = mode => {
    feed = mode;
    document.querySelectorAll("[data-feed]").forEach(item => item.setAttribute("aria-pressed", String(item.dataset.feed === mode)));
    window.bonbonRender?.();
  };
  document.querySelectorAll("[data-feed]").forEach(control => control.addEventListener("click", () => {
    if (["following", "bookmarks"].includes(control.dataset.feed) && needsLogin()) return;
    window.bonbonSelectFeed(control.dataset.feed);
  }));

  async function refreshCommunity() {
    if (!client) return;
    const requests = [
      client.from("profiles").select("user_id,handle,display_name,bio").limit(500),
      client.from("sample_authors").select("id,handle,display_name,bio").limit(100),
      client.from("paper_likes").select("paper_id,user_id,paid").eq("paid", false).limit(2000),
      client.from("comments").select("paper_id").limit(2000),
      client.from("reposts").select("paper_id,user_id,quote,created_at,paper:papers(id,user_id,sample_author_id,author,category,title,blocks,tags,source_paper_id,source_kind,created_at)").order("created_at", { ascending: false }).limit(500),
      client.from("follows").select("follower_id,followed_id").limit(2000),
      client.from("sample_follows").select("follower_id,sample_author_id").limit(2000)
    ];
    if (viewer) requests.push(
      client.from("bookmarks").select("paper_id").eq("user_id", viewer.id).limit(500),
      client.from("user_mutes").select("muted_id").eq("muter_id", viewer.id),
      client.from("user_blocks").select("blocked_id").eq("blocker_id", viewer.id),
      client.from("sample_mutes").select("sample_author_id").eq("muter_id", viewer.id),
      client.from("sample_blocks").select("sample_author_id").eq("blocker_id", viewer.id),
      client.from("moderators").select("user_id").eq("user_id", viewer.id)
    );
    const results = await Promise.all(requests);
    if (results.some(result => result.error)) {
      console.warn("Community data could not be loaded", results.filter(result => result.error).map(result => result.error));
      return;
    }
    profiles = new Map(results[0].data.map(p => [p.user_id, p]));
    for (const p of results[1].data) profiles.set(p.id, { ...p, sample: true });
    likeCounts = new Map(); myLikes = new Set();
    for (const like of results[2].data) {
      likeCounts.set(like.paper_id, numberFor(likeCounts, like.paper_id) + 1);
      if (like.user_id === viewer?.id) myLikes.add(like.paper_id);
    }
    commentCounts = new Map();
    for (const comment of results[3].data) commentCounts.set(comment.paper_id, numberFor(commentCounts, comment.paper_id) + 1);
    reposts = results[4].data;
    repostCounts = new Map(); myReposts = new Set();
    for (const item of reposts) {
      repostCounts.set(item.paper_id, numberFor(repostCounts, item.paper_id) + 1);
      if (item.user_id === viewer?.id) myReposts.add(item.paper_id);
    }
    following = new Set([
      ...results[5].data.filter(item => item.follower_id === viewer?.id).map(item => item.followed_id),
      ...results[6].data.filter(item => item.follower_id === viewer?.id).map(item => item.sample_author_id)
    ]);
    myBookmarks = new Set((results[7]?.data || []).map(item => item.paper_id));
    muted = new Set([...(results[8]?.data || []).map(item => item.muted_id),
      ...(results[10]?.data || []).map(item => item.sample_author_id)]);
    blocked = new Set([...(results[9]?.data || []).map(item => item.blocked_id),
      ...(results[11]?.data || []).map(item => item.sample_author_id)]);
    moderator = !!results[12]?.data?.length;
    window.bonbonRender?.();
  }

  async function likePaper(paper) {
    if (needsLogin()) return;
    if (paper.user_id === viewer.id) { showToast("自分の論文にはいいねできません"); return; }
    const wasLiked = myLikes.has(paper.id);
    const method = wasLiked ? "remove_free_like" : "give_free_like";
    const { error } = await client.rpc(method, { target_paper: paper.id });
    if (error) { showToast("いいねできませんでした。通信状態やブロック設定を確認してください"); return; }
    await refreshCommunity();
    showToast(wasLiked ? "いいねを取り消しました" : "いいねしました");
  }

  async function bookmarkPaper(paper) {
    if (needsLogin()) return;
    const current = myBookmarks.has(paper.id);
    const query = client.from("bookmarks");
    const { error } = current ? await query.delete().eq("paper_id", paper.id).eq("user_id", viewer.id)
      : await query.insert({ paper_id: paper.id, user_id: viewer.id });
    if (error) { showToast("保存状態を変更できませんでした"); return; }
    await refreshCommunity();
    showToast(current ? "保存を解除しました" : "保存しました");
  }

  async function repostPaper(paper, quote = false) {
    if (needsLogin()) return;
    if (paper.user_id === viewer.id) { showToast("自分の論文はリポストできません"); return; }
    if (myReposts.has(paper.id)) {
      if (!confirm("このリポストを取り消しますか？")) return;
      const { error } = await client.from("reposts").delete().eq("paper_id", paper.id).eq("user_id", viewer.id);
      if (error) showToast("取り消せませんでした"); else { await refreshCommunity(); showToast("リポストを取り消しました") }
      return;
    }
    let message = "";
    if (quote) {
      const answer = prompt("引用コメントを入力してください（280文字以内）");
      if (answer === null) return;
      message = answer.trim();
      if (!message || message.length > 280) { showToast("引用コメントを1〜280文字で入力してください"); return; }
    }
    const { error } = await client.from("reposts").insert({ paper_id: paper.id, user_id: viewer.id, quote: message });
    if (error) { showToast("リポストできませんでした"); return; }
    await refreshCommunity();
    showToast(quote ? "引用して共有しました" : "リポストしました");
  }

  async function sharePaper(paper) {
    const url = paperUrl(paper.id);
    try {
      if (navigator.share) await navigator.share({ title: paper.title, url });
      else { await navigator.clipboard.writeText(url); showToast("論文のURLをコピーしました"); }
    } catch (error) {
      if (error.name !== "AbortError") prompt("このURLをコピーしてください", url);
    }
  }

  function communityCardActions(paper, foot) {
    const actions = el("div", "social-actions");
    const likes = numberFor(likeCounts, paper.id);
    const comments = numberFor(commentCounts, paper.id);
    const reposts = numberFor(repostCounts, paper.id);
    actions.append(
      iconButton("like", `いいね ${likes}件${myLikes.has(paper.id) ? "・もう一度押すと取り消し" : ""}`, () => likePaper(paper), { count: likes, active: myLikes.has(paper.id) }),
      iconButton("comment", `コメント ${comments}件`, () => window.bonbonOpenPaper?.(paper), { count: comments }),
      iconButton("repost", `リポスト ${reposts}件`, () => repostPaper(paper), { count: reposts, active: myReposts.has(paper.id) }),
      iconButton("bookmark", myBookmarks.has(paper.id) ? "保存済み" : "保存", () => bookmarkPaper(paper), { active: myBookmarks.has(paper.id) }),
      iconButton("share", "共有", () => sharePaper(paper))
    );
    foot.append(actions);
  }

  async function loadComments(paper, container) {
    const { data, error } = await client.from("comments")
      .select("id,user_id,body,created_at").eq("paper_id", paper.id)
      .order("created_at", { ascending: true }).limit(100);
    container.replaceChildren();
    if (error) { container.append(el("p", "hint", "コメントを読み込めませんでした")); return; }
    if (!data.length) container.append(el("p", "hint", "まだコメントはありません。"));
    for (const item of data) {
      const box = el("div", "comment");
      box.append(el("b", "", authorName(item.user_id)), el("p", "", item.body));
      if (ownOrModerated(item.user_id)) box.append(button("削除", async () => {
        if (!confirm("このコメントを削除しますか？")) return;
        const { error: removeError } = await client.from("comments").delete().eq("id", item.id);
        if (removeError) showToast("コメントを削除できませんでした");
        else { await loadComments(paper, container); await refreshCommunity(); }
      }, "social-action dangerbutton"));
      container.append(box);
    }
  }

  window.bonbonReadActions = (paper, content) => {
    const actions = el("div", "read-actions");
    const likes = numberFor(likeCounts, paper.id);
    const reposts = numberFor(repostCounts, paper.id);
    actions.append(
      iconButton("like", `いいね ${likes}件${myLikes.has(paper.id) ? "・もう一度押すと取り消し" : ""}`, () => likePaper(paper), { count: likes, active: myLikes.has(paper.id), showLabel: true }),
      iconButton("comment", `コメント ${numberFor(commentCounts, paper.id)}件`, () => content.querySelector(".comment-list")?.scrollIntoView({ behavior: "smooth" }), { count: numberFor(commentCounts, paper.id), showLabel: true }),
      iconButton("bookmark", myBookmarks.has(paper.id) ? "保存済み" : "保存", () => bookmarkPaper(paper), { active: myBookmarks.has(paper.id), showLabel: true }),
      iconButton("repost", `リポスト ${reposts}件`, () => repostPaper(paper), { count: reposts, active: myReposts.has(paper.id), showLabel: true }),
      button("引用して共有", () => repostPaper(paper, true)),
      button("追試を書く", () => { document.getElementById("read-dialog").close(); window.bonbonStartLinkedPaper?.(paper, "replication") }),
      button("引用して論文を書く", () => { document.getElementById("read-dialog").close(); window.bonbonStartLinkedPaper?.(paper, "citation") }),
      button("URLを共有", () => sharePaper(paper))
    );
    content.append(actions, el("h3", "", "コメント"));
    const comments = el("div", "comment-list");
    content.append(comments);
    loadComments(paper, comments);
    if (!viewer) {
      content.append(button("コメントするにはログイン", () => needsLogin(), "smallbutton"));
      return;
    }
    const form = el("form", "field"), area = el("textarea");
    area.maxLength = 500; area.placeholder = "感想や質問を書く（500字以内）"; area.required = true;
    const send = button("コメントを送る", () => {}, "primary"); send.type = "submit";
    form.append(area, send);
    form.addEventListener("submit", async event => {
      event.preventDefault(); const body = area.value.trim();
      if (!body || body.length > 500) return;
      send.disabled = true;
      const { error } = await client.from("comments").insert({ paper_id: paper.id, user_id: viewer.id, body });
      send.disabled = false;
      if (error) showToast("コメントを送れませんでした");
      else { area.value = ""; await loadComments(paper, comments); await refreshCommunity(); showToast("コメントしました") }
    });
    content.append(form);
  };

  async function showProfile(userId) {
    const person = profiles.get(userId);
    if (!person) { showToast("プロフィールを読み込めませんでした"); return; }
    profileContent.replaceChildren();
    profileContent.append(el("h3", "", person.display_name),
      el("p", "hint", `@${person.handle}${person.sample ? " · 公式サンプル" : ""}`),
      el("p", "", person.bio || "自己紹介はまだありません。"));
    const [followersResult, papersResult] = await Promise.all([
      person.sample ? client.from("sample_follows").select("follower_id").eq("sample_author_id", userId)
        : client.from("follows").select("follower_id").eq("followed_id", userId),
      client.from("papers").select("id,title,created_at")
        .eq(person.sample ? "sample_author_id" : "user_id", userId)
        .order("created_at", { ascending: false }).limit(20)
    ]);
    const stats = el("div", "profile-stats");
    stats.append(el("span", "", `フォロワー ${followersResult.data?.length || 0}人`), el("span", "", `論文 ${papersResult.data?.length || 0}本`));
    profileContent.append(stats);
    if (viewer?.id === userId) {
      const form = el("form", ""), name = el("input"), handle = el("input"), bio = el("textarea");
      name.value = person.display_name; name.maxLength = 30; name.required = true;
      handle.value = person.handle; handle.maxLength = 40; handle.pattern = "[a-z0-9_]{3,40}"; handle.required = true;
      bio.value = person.bio || ""; bio.maxLength = 200;
      for (const [label, field] of [["表示名", name], ["ユーザーID（英小文字・数字・_）", handle], ["自己紹介", bio]]) {
        const wrap = el("div", "field"); wrap.append(el("label", "", label), field); form.append(wrap);
      }
      const save = button("プロフィールを保存", () => {}, "primary"); save.type = "submit"; form.append(save);
      form.addEventListener("submit", async event => {
        event.preventDefault(); if (!form.reportValidity()) return;
        const { error } = await client.from("profiles").update({ display_name: name.value.trim(), handle: handle.value.trim(), bio: bio.value.trim() }).eq("user_id", viewer.id);
        if (error) showToast("保存できませんでした。ユーザーIDの重複を確認してください");
        else { await refreshCommunity(); showToast("プロフィールを更新しました"); showProfile(userId); }
      });
      profileContent.append(form);
    } else {
      const actions = el("div", "read-actions");
      actions.append(button(following.has(userId) ? "フォロー解除" : "フォロー", async () => {
        if (needsLogin()) return;
        const table = person.sample ? "sample_follows" : "follows";
        const targetColumn = person.sample ? "sample_author_id" : "followed_id";
        const { error } = following.has(userId)
          ? await client.from(table).delete().eq("follower_id", viewer.id).eq(targetColumn, userId)
          : await client.from(table).insert({ follower_id: viewer.id, [targetColumn]: userId });
        if (error) showToast("フォローを変更できませんでした"); else { await refreshCommunity(); showProfile(userId); }
      }));
      for (const [kind, active, table, ownerColumn, targetColumn] of [
        ["ミュート", muted.has(userId), person.sample ? "sample_mutes" : "user_mutes", "muter_id", person.sample ? "sample_author_id" : "muted_id"],
        ["ブロック", blocked.has(userId), person.sample ? "sample_blocks" : "user_blocks", "blocker_id", person.sample ? "sample_author_id" : "blocked_id"]
      ]) actions.append(button(active ? `${kind}解除` : kind, async () => {
        if (needsLogin()) return;
        const { error } = active ? await client.from(table).delete().eq(ownerColumn, viewer.id).eq(targetColumn, userId)
          : await client.from(table).insert({ [ownerColumn]: viewer.id, [targetColumn]: userId });
        if (error) showToast(`${kind}を変更できませんでした`);
        else { await refreshCommunity(); showProfile(userId); }
      }));
      profileContent.append(actions);
    }
    profileContent.append(el("h3", "", "投稿した論文"));
    for (const paper of papersResult.data || []) profileContent.append(button(paper.title, () => {
      profileDialog.close(); window.bonbonOpenPaperById?.(paper.id);
    }, "author-button"));
    if (!profileDialog.open) profileDialog.showModal();
  }
  window.bonbonOpenProfile = showProfile;
  document.getElementById("profile-button").addEventListener("click", () => {
    if (needsLogin()) return; showProfile(viewer.id);
  });

  async function showNotifications() {
    if (needsLogin()) return;
    noticesContent.replaceChildren(el("p", "hint", "通知を読み込んでいます…"));
    noticesDialog.showModal();
    const { data, error } = await client.from("notifications")
      .select("id,actor_id,paper_id,kind,created_at,read_at").eq("recipient_id", viewer.id)
      .order("created_at", { ascending: false }).limit(50);
    noticesContent.replaceChildren();
    if (error) { noticesContent.append(el("p", "hint", "通知を読み込めませんでした")); return; }
    if (!data.length) noticesContent.append(el("p", "hint", "まだ通知はありません。"));
    const labels = { like: "いいね", comment: "コメント", follow: "フォロー", repost: "リポスト" };
    for (const item of data) {
      const row = el("div", "notice-item");
      row.append(button(`${authorName(item.actor_id)}さんから${labels[item.kind]}がありました`, () => {
        noticesDialog.close();
        if (item.paper_id) window.bonbonOpenPaperById?.(item.paper_id);
        else showProfile(item.actor_id);
      }, "author-button"));
      noticesContent.append(row);
    }
    const unread = data.filter(item => !item.read_at).map(item => item.id);
    if (unread.length) await client.from("notifications").update({ read_at: new Date().toISOString() }).in("id", unread);
    document.getElementById("notices-button").textContent = "通知";
  }
  document.getElementById("notices-button").addEventListener("click", showNotifications);

  async function openPaperById(id) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return;
    let paper = window.bonbonPublicPapers?.().find(item => item.id === id);
    if (!paper) {
      const { data, error } = await client.from("papers").select("id,user_id,sample_author_id,author,category,title,blocks,tags,source_paper_id,source_kind,created_at").eq("id", id).maybeSingle();
      if (error || !data) { showToast("論文が見つかりませんでした"); return; }
      paper = { ...data, user_id: data.user_id || data.sample_author_id,
        sample: !!data.sample_author_id, remote: true };
    }
    const readDialog = document.getElementById("read-dialog");
    if (readDialog.open) readDialog.close();
    window.bonbonOpenPaper?.(paper);
  }
  window.bonbonOpenPaperById = openPaperById;
  window.addEventListener("hashchange", () => {
    const match = location.hash.match(/^#paper=([0-9a-f-]{36})$/i);
    if (match && client) openPaperById(match[1]);
  });

  function start(event) {
    client = event.detail.client;
    const originalCardActions = window.bonbonCardActions;
    window.bonbonCardActions = (paper, foot) => {
      originalCardActions?.(paper, foot);
      communityCardActions(paper, foot);
    };
    viewer = window.bonbonCurrentUser?.() || null;
    refreshCommunity();
    const match = location.hash.match(/^#paper=([0-9a-f-]{36})$/i);
    if (match) openPaperById(match[1]);
  }
  window.addEventListener("bonbon:authchange", event => {
    viewer = event.detail.user;
    refreshCommunity();
  });
  if (window.bonbonClient) start({ detail: { client: window.bonbonClient } });
  else window.addEventListener("bonbon:ready", start, { once: true });
})();
