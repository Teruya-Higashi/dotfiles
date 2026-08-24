---
name: reply-pr-review
description: PRのレビューコメントを精査し、返信を投稿する。PR番号またはURLを引数に取る。自分のPRに付いたレビューコメントへの対応・返信や、「レビューに返信して」と依頼されたときに使用する。
---

# Reply PR Review

指定したPRのレビューコメントを精査し、修正の必要性を判定した上で返信を投稿する。

**REQUIRED SUB-SKILL:** GitHubへの情報取得・投稿で`gh`を使うため、`gh-ops`を読み、そのルール（autolink回避、AI Generatedバッジ、コンテンツの渡し方等）に従う。

## 引数

```text
/reply-pr-review [PR番号 or PR URL] [--watch] [--fix]
```

- **PR番号を指定**: `5130`や`https://github.com/.../pull/5130`
- **省略時**: 現在のブランチに紐づくPRを自動検出

| オプション | 説明 |
|---|---|
| `--fix` | 手順6のユーザー確認をスキップし、対応推奨の修正（commit + push）から返信投稿まで確認なしで行う。PR authorが自分以外なら拒否する |
| `--watch` | PRを監視し、未返信レビューコメントを検出するたびに自動実行する |

`--watch`指定時は[`../review-patch/references/watch-mode.md`](../review-patch/references/watch-mode.md)を全文読み、それに従う。

## 手順

### 1. PRの特定

引数が指定されていない場合、現在のブランチからPRを特定する:

```bash
# 現在のブランチの PR を検出
gh pr list --head $(git branch --show-current) --json number,title,url
```

引数がURLの場合はPR番号を抽出する。

### 2. レビューコメントの取得

指摘はインラインコメントだけでなくサマリコメント（レビュー本文・PR会話コメント）にも含まれることがあるため、両方を取得する。

```bash
# (a) インラインコメント: diff の行に紐づくコメント
gh api repos/:owner/:repo/pulls/{pr_number}/comments \
  --jq '.[] | {id, user: .user.login, path, line, body, in_reply_to_id, created_at}'

# (b) サマリコメント①: レビュー本文（review 提出時の総評 body）
gh api repos/:owner/:repo/pulls/{pr_number}/reviews \
  --jq '.[] | select(.body != "") | {id, user: .user.login, state, body, submitted_at}'

# (c) サマリコメント②: PR 会話コメント（issue comment）
gh api repos/:owner/:repo/issues/{pr_number}/comments \
  --jq '.[] | {id, user: .user.login, body, created_at}'
```

- **(a) インラインコメント**: `path:line`に紐づき、`in_reply_to`でスレッド返信できる
- **(b)(c) サマリコメント**: `path:line`に紐づかない総評・指摘一覧を含みうる。スレッド返信の口がないため、後述のとおりPR会話コメントとして返信する
- 自分（`![AI Generated]`バッジ付き）が過去に投稿したサマリ・返信は対象から除外する

### 3. 未返信コメントのフィルタリング

既に返信済みのコメントをスキップする。返信の判定方法はコメント種別で異なる。

#### (a) インラインコメント

スレッドに自分の返信（`in_reply_to_id`が対象コメントID）があればスキップする:

```bash
# 各コメントの返信を確認
gh api repos/:owner/:repo/pulls/{pr_number}/comments \
  --jq '.[] | select(.in_reply_to_id == {comment_id}) | .id'
```

返信が0件のコメントのみを対象とする。

#### (b) サマリコメント

レビュー本文・会話コメントはスレッド返信の口がないため、返信はPR会話コメントとして投稿する（後述）。再実行時の二重投稿を防ぐため、返信本文末尾に隠しマーカー`<!-- reply-pr-review:summary:{target_id} -->`を埋め込み、既存の会話コメントに同じマーカーが存在するサマリはスキップする:

```bash
# 返信済みサマリの target_id を抽出
gh api repos/:owner/:repo/issues/{pr_number}/comments \
  --jq '.[].body | capture("reply-pr-review:summary:(?<id>[0-9]+)") | .id'
```

抽出されたIDに一致するサマリはスキップする。

対象コメント（インライン・サマリ合計）が0件の場合は「未返信のレビューコメントはありません」と表示して終了する。

### 4. コメントの精査

各コメントについて以下を実施する。

1. **タグ種別の判別**: コメント先頭のバッジや本文からカテゴリを抽出する。タグ体系は[`../review-patch/references/review-policy.md`](../review-patch/references/review-policy.md)の4タグ（critical / should / nits / ask）に従う。他体系のタグは深刻度の近いタグへ読み替える。

   サマリコメントはバッジを持たないことが多い。その場合は本文から指摘の深刻度を読み取り、上記カテゴリに当てはめる。

2. **対象コードの読解**: コメントが指す`path:line`のファイルをReadツールで読み、コメント内容の妥当性を検証する
   - サマリコメントは`path:line`に紐づかない。本文から対象ファイル・観点を読み取り、該当箇所をReadで検証する
   - サマリが個別インライン指摘の要約にすぎず、新規の指摘を含まない場合は、その旨を記録してインライン側の対応に集約する（重複対応・重複返信をしない）

3. **判定**: 以下のいずれかに分類する
   - **対応推奨**: 指摘が妥当で修正すべき（`critical`は特に対応を推奨）
   - **現状維持**: 意図的な設計であり修正不要（理由を明記）

### 5. 判定結果の提示

ユーザーに一覧表を提示する:

```markdown
| No. | ソース | ファイル | 種別 | 内容 | 判定 |
|---:|---|---|---|---|---|
| 1 | インライン | path/to/file.ts | ask | 要約 | **対応推奨** — 理由 |
| 2 | インライン | path/to/other.ts | nits | 要約 | **現状維持** — 理由 |
| 3 | サマリ | (総評) | should | 要約 | **対応推奨** — 理由 |
```

`ソース`列でインラインコメントとサマリコメント（レビュー本文・会話コメント）を区別する。サマリで`path:line`に紐づかない指摘は`ファイル`列を`(総評)`等とする。

### 6. ユーザー確認

AskUserQuestionでユーザーに確認を取る:

- どのコメントに対応するか（multiSelect）
- コード修正が必要なものがある場合はその旨を説明

**重要**: ユーザーの確認なしにコード修正・返信投稿を行わない。ただし`--fix`指定時はフラグ指定を確認済みとみなし、この手順を行わず判定どおり（対応推奨 → 修正、現状維持 → 返信のみ）に進む。

### 7. コード修正（必要な場合）

ユーザーが対応を承認したコメント（`--fix`指定時は対応推奨と判定したコメント）について:

1. 対象ファイルを編集する
2. プロジェクト既定の検証手順（task runner定義や`AGENTS.md`等で確認）に従い、変更に対応するlint / testを実行する

`--fix`指定時は修正をcommit + pushまで行う（返信に記載するコミットハッシュを確定させるため）。

### 8. 返信の投稿

全コメント（対応済み・現状維持の両方、インライン・サマリの両方）に返信を投稿する。返信先の種別によってAPIコールが異なる（後述）。

#### 返信フォーマット

```markdown
![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)

{返信本文}
```

- **対応した場合**: 修正内容と対応コミットハッシュを記載
- **現状維持の場合**: 現状維持の理由を簡潔に説明
- 挨拶文（「ご指摘ありがとうございます」「ご確認ありがとうございます」等）は不要。本題のみ簡潔に書く

#### APIコール

`gh api`でのコンテンツの渡し方は`gh-ops`の「コンテンツの渡し方」節を参照する（`--input`を使う）。

**(a) インラインコメントへの返信**: スレッド返信として`in_reply_to`を指定する。

```bash
gh api repos/:owner/:repo/pulls/{pr_number}/comments \
  --method POST --input - <<'EOF'
{"body": "![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)\n\n{返信本文}", "in_reply_to": {comment_id}}
EOF
```

**(b) サマリコメントへの返信**: スレッド返信の口がないため、PR会話コメント（issue comment）として投稿する。どの指摘への返信かが分かるよう本文で対象を明示し、末尾に二重投稿防止の隠しマーカーを付与する（`{target_id}`は手順2で取得したレビュー本文or会話コメントの`id`）。

```bash
gh api repos/:owner/:repo/issues/{pr_number}/comments \
  --method POST --input - <<'EOF'
{"body": "![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)\n\n{どのサマリ指摘への返信かを明示した本文}\n\n<!-- reply-pr-review:summary:{target_id} -->"}
EOF
```

複数のサマリ指摘に返信する場合は、指摘ごとに1件ずつ投稿するか、1件の会話コメントにまとめてもよい。まとめる場合はマーカーを対象分すべて列挙する。

## 注意事項

- 返信には必ず`![AI Generated]`バッジを付与する（`gh-ops`の「AI Generatedバッジ」節を参照）
- 指摘はインラインコメントだけでなくサマリコメント（レビュー本文・PR会話コメント）にも含まれうるため、両方を確認する
- 二重投稿しない（冪等性）: インラインはスレッドの`in_reply_to_id`、サマリは会話コメント内の隠しマーカー`reply-pr-review:summary:{target_id}`で判定する
- コード修正はユーザー確認後にのみ実施する（`--fix`指定時はフラグ指定を確認済みとみなす）
- すべてのユーザー（bot含む）のレビューコメント・サマリコメントを対象とする
