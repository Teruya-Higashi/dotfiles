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
- 除外するのは自分の返信と添付companion commentだけ。インラインは`in_reply_to_id`、サマリは`reply-pr-review:summary:`、添付commentは`<!-- session-media:attachments:{PR番号} -->`のhidden marker（他スキルの投稿分を含む）を直接証拠にする。`![AI Generated]`、bot、時刻、件数を除外条件にしない。

未返信は次の規則で判定する。

- インライン: 対象comment IDへの自分の`in_reply_to_id`がない
- サマリ: `<!-- reply-pr-review:summary:{target_id} -->`付き返信がない
- サマリ内の各項目: 既存インラインと内容まで一致するものだけ集約する
- 一致しない項目: 共通判定表の独立行にする
- 添付companion comment: 共通markerで除外し、サマリ指摘として抽出しない
- 対象0件: 「未返信のレビューコメントはありません」と表示して終了する

## GitHub の修正と返信

`--fix`は自分の同一repository PRだけで使い、authorが自分以外、またはfork PRなら拒否する。対応推奨の全行をプロジェクト所定のvalidationで検証してcommit + pushする。対応できない場合は判定を現状維持へ改め、理由を返信する。対応した返信には修正内容とコミットハッシュを記載する。

返信には必ず AI Generated バッジを付ける。

現在のセッションにユーザー添付メディア（過去ターンの台帳登録分を含む）がある場合は、[`../../create-pr/references/media-attachments.md`](../../create-pr/references/media-attachments.md)に従って候補判定と確認を行う。確認済み添付がある場合、返信APIは`--attach`非対応なので、先にcompanion commentを1件投稿し、そのURLを各返信に記載する。本文にはAI Generatedバッジ、添付の目的・返信対象と`<!-- session-media:attachments:{PR番号} -->`を付ける。返信だけ失敗した再試行では台帳・対象・添付内容が一致する既存commentのURLを再利用し、重複投稿しない。添付投稿が失敗・部分成功・結果不明なら返信を投稿せず、既存commentの状態と不足分を報告する。

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

## 返信したインラインの resolve

返信を投稿したインラインは、対応済み・現状維持を問わずthreadをresolveする。サマリ（PR会話コメント）にはthreadがない。ローカルsourceのresolved eventには適用しない。

1. 投稿した返信を再取得し、本文と`in_reply_to_id`が対象commentに一致することを確認する。
2. GraphQLで対象PRのthreadを取得し、対象comment IDを`databaseId`に含むthreadを特定する。thread一覧は`--paginate`で全ページ取得する。

```bash
gh api graphql --paginate -f query='query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
    reviewThreads(first:100,after:$endCursor){
      nodes { id isResolved comments(first:100){ nodes { databaseId } commentsPageInfo: pageInfo { hasNextPage endCursor } } }
      pageInfo { hasNextPage endCursor }
    }
  } }
}' -f owner='{owner}' -f repo='{repo}' -F pr={pr_number}
```

commentsの`commentsPageInfo.hasNextPage`がtrueで対象が見つからないthreadは、次のqueryでcommentsも全ページ取得する。最初の100件だけで対象なしと判定しない。外側のqueryではcommentsのpageInfoをaliasにし、`gh --paginate`がthread一覧のcursorだけを辿るようにする。

```bash
gh api graphql --paginate -f query='query($id:ID!,$endCursor:String){
  node(id:$id){ ... on PullRequestReviewThread {
    id isResolved comments(first:100,after:$endCursor){
      nodes { databaseId } pageInfo { hasNextPage endCursor }
    }
  } }
}' -f id='{thread_id}'
```

3. 対象threadが一意に特定でき、まだunresolvedの場合だけ、次のmutationを実行する。取得失敗、対象なし、複数候補ではresolveせず理由を報告する。

```bash
gh api graphql -f query='mutation($id:ID!){
  resolveReviewThread(input:{threadId:$id}){ thread { id isResolved } }
}' -f id='{thread_id}'
```

4. 同じthread IDを再取得して`isResolved: true`を確認してから完了扱いにする。すでにresolvedならmutationは省略する。GraphQLの`errors`、権限不足、再取得失敗は未完了として報告する。

```bash
gh api graphql -f query='query($id:ID!){
  node(id:$id){ ... on PullRequestReviewThread { id isResolved } }
}' -f id='{thread_id}'
```

返信成功後にresolveだけ失敗した場合は対象comment ID、返信ID、thread IDを保持し、返信を重複投稿せずresolveと再取得確認だけを再試行する。この実行で返信した対象だけに適用し、過去の返信済みthreadやreviewerがreopenしたthreadを一括resolveしない。
