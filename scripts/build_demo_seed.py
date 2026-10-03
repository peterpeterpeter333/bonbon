"""Build an idempotent SQL seed for the 10 clearly labelled sample authors."""

import json
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTHORS = json.loads((ROOT / "supabase/demo-content.json").read_text())
EXPANSIONS = {}
FEATURED = json.loads((ROOT / "supabase/demo-featured.json").read_text())
current_author = None
for line in (ROOT / "supabase/demo-expansions.txt").read_text().splitlines():
    if line.startswith("#"):
        current_author = line[1:]
        assert current_author not in EXPANSIONS
        EXPANSIONS[current_author] = []
    else:
        plan, discussion = line.split("|", 1)
        EXPANSIONS[current_author].append((plan, discussion))
NAMESPACE = uuid.UUID("3f97b607-b8e3-4b3d-9932-145338211bbb")


def sql(value):
    if isinstance(value, uuid.UUID):
        return f"'{value}'"
    if isinstance(value, str):
        return "'" + value.replace("'", "''") + "'"
    raise TypeError(value)


def main():
    assert len(AUTHORS) == 10
    assert all(len(author["posts"]) == 10 for author in AUTHORS)
    assert set(EXPANSIONS) == {author["handle"] for author in AUTHORS}
    assert set(FEATURED) == set(EXPANSIONS)
    assert all(len(items) == 10 for items in EXPANSIONS.values())
    author_rows = []
    paper_rows = []
    for author in AUTHORS:
        aid = uuid.uuid5(NAMESPACE, "author:" + author["handle"])
        author_rows.append("(" + ",".join(map(sql, [aid, author["handle"], author["name"], author["bio"]])) + ")")
    for post_number in range(10):
        for author_number, author in enumerate(AUTHORS):
            item = author["posts"][post_number]
            title, body, category, tags = item[:4]
            image = item[4] if len(item) > 4 else None
            assert 1 <= len(title) <= 70 and 1 <= len(body) <= 500
            assert category in {"暮らし", "食べもの", "人間関係"}
            assert len(tags) <= 5 and all(1 <= len(t) <= 20 for t in tags)
            aid = uuid.uuid5(NAMESPACE, "author:" + author["handle"])
            pid = uuid.uuid5(NAMESPACE, "paper:" + author["handle"] + ":" + str(post_number))
            plan, discussion = EXPANSIONS[author["handle"]][post_number]
            blocks = [
                {"type": "text", "heading": "問いと仮説", "body": body},
                {"type": "text", "heading": "検証計画（未実施）", "body": plan},
            ]
            if post_number == 0:
                blocks.append({"type": "text", "heading": "反証条件", "body": FEATURED[author["handle"]][0]})
            blocks.append({"type": "text", "heading": "考察と反例", "body": discussion})
            if post_number == 0:
                blocks.append({"type": "text", "heading": "仮結論", "body": FEATURED[author["handle"]][1]})
            assert all(len(block["body"]) <= 500 for block in blocks)
            if image:
                assert image in {"sock-detective.jpg", "checkout-lines.jpg", "reply-at-night.jpg", "umbrella-choices.jpg"}
                blocks.append({"type": "image", "asset": "images/" + image, "caption": "この投稿のために生成した挿絵"})
            offset = (post_number * 10 + author_number) * 3
            fields = [sql(pid), sql(aid), sql(author["name"]), sql(category), sql(title),
                      sql(json.dumps(blocks, ensure_ascii=False, separators=(",", ":"))) + "::jsonb",
                      "ARRAY[" + ",".join(map(sql, tags)) + "]::text[]",
                      f"now() - interval '{offset} hours'"]
            paper_rows.append("(" + ",".join(fields) + ")")
    output = [
        "-- 公式サンプルのみ。実ログイン用のユーザーは作りません。",
        "-- demo-support.sql の後に実行。再実行すると同じ100件の本文を更新します。",
        "insert into public.sample_authors(id,handle,display_name,bio) values",
        ",\n".join(author_rows) + " on conflict(id) do nothing;",
        "insert into public.papers(id,sample_author_id,author,category,title,blocks,tags,created_at) values",
    ]
    output.append(",\n".join(paper_rows) + " on conflict(id) do update set "
                  "author=excluded.author, category=excluded.category, title=excluded.title, "
                  "blocks=excluded.blocks, tags=excluded.tags, created_at=excluded.created_at "
                  "where public.papers.sample_author_id=excluded.sample_author_id;")
    (ROOT / "supabase/demo-seed.sql").write_text("\n".join(output) + "\n")
    print("Wrote 10 sample authors and 100 posts")


if __name__ == "__main__":
    main()
