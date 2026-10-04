"""Build the curated comic sample seed. Only existing sample papers are replaced."""

import json
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAPERS = json.loads((ROOT / "supabase/comic-papers.json").read_text())
NAMESPACE = uuid.UUID("3f97b607-b8e3-4b3d-9932-145338211bbb")
AUTHORS = {
    "nemuri_lab": ("ねむり計測室", "眠気と休日を調べる公式サンプル。実在の利用者ではありません。"),
    "kitchen_notes": ("台所の観察者", "台所の小事件を調べる公式サンプル。実在の利用者ではありません。"),
    "train_window": ("通勤の窓際", "移動と待ち合わせを調べる公式サンプル。実在の利用者ではありません。"),
    "reply_pending": ("返信保留中", "会話のすれ違いを調べる公式サンプル。実在の利用者ではありません。"),
    "math_in_pocket": ("ポケットの数学", "日常の計算違いを調べる公式サンプル。実在の利用者ではありません。"),
    "town_margin": ("まちの余白", "街で見つけた疑問を調べる公式サンプル。実在の利用者ではありません。"),
    "otaku_shelf": ("オタクの棚", "趣味と時間を調べる公式サンプル。実在の利用者ではありません。"),
    "word_collector": ("言葉の採集者", "言葉の妙な働きを調べる公式サンプル。実在の利用者ではありません。"),
    "object_philosophy": ("ものの哲学", "道具と習慣を調べる公式サンプル。実在の利用者ではありません。"),
    "rainy_statistics": ("雨の日統計", "天気と体感を調べる公式サンプル。実在の利用者ではありません。"),
}
IMAGES = {"on-my-way.jpg", "microwave-second.jpg", "anything-is-fine.jpg"}


def sql(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    assert len(PAPERS) == 12
    assert {paper["handle"] for paper in PAPERS} == set(AUTHORS)
    assert len({paper["title"] for paper in PAPERS}) == len(PAPERS)
    author_ids = {handle: uuid.uuid5(NAMESPACE, "author:" + handle) for handle in AUTHORS}
    paper_ids = [uuid.uuid5(NAMESPACE, "comic:" + paper["title"]) for paper in PAPERS]
    author_rows = []
    paper_rows = []
    for handle, (name, bio) in AUTHORS.items():
        assert len(name) <= 30 and len(bio) <= 200
        author_rows.append("(" + ",".join(map(sql, [author_ids[handle], handle, name, bio])) + ")")
    for index, paper in enumerate(PAPERS):
        handle = paper["handle"]
        title = paper["title"]
        category = paper["category"]
        tags = paper["tags"]
        assert 1 <= len(title) <= 70
        assert category in {"暮らし", "食べもの", "人間関係"}
        assert len(tags) <= 5 and all(1 <= len(tag) <= 20 for tag in tags)
        blocks = []
        for heading, body in paper["blocks"]:
            assert len(heading) <= 40 and len(body) <= 500
            blocks.append({"type": "text", "heading": heading, "body": body})
        assert len(blocks) >= 3
        if image := paper.get("image"):
            assert image in IMAGES and (ROOT / "dist/images" / image).is_file()
            blocks.insert(2, {"type": "image", "asset": "images/" + image, "caption": "この論文のために生成した挿絵"})
        fields = [
            sql(paper_ids[index]), sql(author_ids[handle]), sql(AUTHORS[handle][0]),
            sql(category), sql(title),
            sql(json.dumps(blocks, ensure_ascii=False, separators=(",", ":"))) + "::jsonb",
            "ARRAY[" + ",".join(map(sql, tags)) + "]::text[]",
            f"now() - interval '{index} hours'",
        ]
        paper_rows.append("(" + ",".join(fields) + ")")
    output = [
        "-- 既存の公式サンプル100件のみを12件の新作へ入れ替えます。一般ユーザーの投稿は削除しません。",
        "-- demo-support.sql の画像許可設定を更新してから実行してください。",
        "begin;",
        "insert into public.sample_authors(id,handle,display_name,bio) values",
        ",\n".join(author_rows) + " on conflict(id) do update set display_name=excluded.display_name,bio=excluded.bio;",
        "delete from public.papers where sample_author_id in (" + ",".join(map(sql, author_ids.values())) + ")",
        "  and id not in (" + ",".join(map(sql, paper_ids)) + ");",
        "insert into public.papers(id,sample_author_id,author,category,title,blocks,tags,created_at) values",
        ",\n".join(paper_rows) + " on conflict(id) do update set "
        "author=excluded.author,category=excluded.category,title=excluded.title,"
        "blocks=excluded.blocks,tags=excluded.tags,created_at=excluded.created_at "
        "where public.papers.sample_author_id=excluded.sample_author_id;",
        "commit;",
    ]
    (ROOT / "supabase/demo-seed.sql").write_text("\n".join(output) + "\n")
    print("Wrote 10 sample authors and 12 comic papers; old sample papers will be removed")


if __name__ == "__main__":
    main()
