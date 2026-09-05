# GitHub source 手順

`--local` がないときにこの reference を Read tool で全文読む。GitHub の既存経路を使う。

## PR の特定

引数がない場合、現在のブランチから PR を特定する。

```bash
gh pr list --head $(git branch --show-current) --json number,title,url
```

引数が URL の場合は PR 番号を抽出する。

## レビューコメントの取得と未返信判定

インラインコメント、レビュー本文、PR 会話コメントを取得する。

```bash
gh api --paginate repos/:owner/:repo/pulls/{pr_number}/comments \
  --jq '.[] | {id, user: .user.login, path, line, body, in_reply_to_id, created_at}'
gh api --paginate repos/:owner/:repo/pulls/{pr_number}/reviews \
  --jq '.[] | select(.body != "") | {id, user: .user.login, state, body, submitted_at}'
gh api --paginate repos/:owner/:repo/issues/{pr_number}/comments \
  --jq '.[] | {id, user: .user.login, body, created_at}'
```

- インラインは `path:line` に紐づき、`in_reply_to` でスレッド返信できる。
- レビュー本文・PR 会話コメントは `path:line` に紐づかないため、PR 会話コメントで返信する。
- 除外するのは自分の返信だけ。インラインは `in_reply_to_id`、サマリは `reply-pr-review:summary:` hidden marker を直接証拠にする。`![AI Generated]`、bot、時刻、件数を除外条件にしない。

未返信は次の規則で判定する。

- インライン: 対象comment IDへの自分の`in_reply_to_id`がない
- サマリ: `<!-- reply-pr-review:summary:{target_id} -->`付き返信がない
- サマリ内の各項目: 既存インラインと内容まで一致するものだけ集約する
- 一致しない項目: 共通判定表の独立行にする
- 対象0件: 「未返信のレビューコメントはありません」と表示して終了する

## GitHub の修正と返信

`--fix`は自分の同一repository PRだけで使い、authorが自分以外、またはfork PRなら拒否する。対応推奨の全行をプロジェクト所定のvalidationで検証してcommit + pushする。対応できない場合は判定を現状維持へ改め、理由を返信する。対応した返信には修正内容とコミットハッシュを記載する。

返信には必ず AI Generated バッジを付ける。

```markdown
![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)

{返信本文}
```

インラインには `in_reply_to` を指定して投稿する。

```bash
gh api repos/:owner/:repo/pulls/{pr_number}/comments \
  --method POST --input - <<'EOF'
{"body": "![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)\n\n{返信本文}", "in_reply_to": {comment_id}}
EOF
```

サマリには、対象を明示し `reply-pr-review:summary:{target_id}` marker を末尾に付けた PR 会話コメントを投稿する。

```bash
gh api repos/:owner/:repo/issues/{pr_number}/comments \
  --method POST --input - <<'EOF'
{"body": "![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)\n\n{どのサマリ指摘への返信かを明示した本文}\n\n<!-- reply-pr-review:summary:{target_id} -->"}
EOF
```

複数のサマリ指摘には、指摘ごとに投稿するか、1件に対象markerをすべて列挙する。`gh api`のコンテンツは`gh-ops`の`--input`手順に従う。
