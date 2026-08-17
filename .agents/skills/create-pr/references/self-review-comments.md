# Self-review Comments

ユーザーがセルフレビューコメントの投稿も明示し、`create-pr`本体の事前選択を終えた場合だけ使う。

## 1. 投稿位置を検証する

```bash
gh pr view "{pr_number}" --repo "{base_repo}" \
  --json headRefOid,files,url
gh pr diff "{pr_number}" --repo "{base_repo}"
```

各コメントのpath、line、sideが現在のPR diffに存在することを確認する。追加・変更行は`RIGHT`、削除行は`LEFT`を使う。diff更新で位置が古くなっていれば、推測で投稿せず候補を作り直して再確認する。

## 2. 1つのCOMMENTレビューにまとめる

ユーザーが選択したコメントだけからJSON payloadを一時ファイルへ作る。本文冒頭にはAI Generatedバッジを付ける。

```json
{
  "commit_id": "{headRefOid}",
  "event": "COMMENT",
  "body": "![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)\n\nセルフレビューコメントを追加します。",
  "comments": [
    {
      "path": "path/to/file.go",
      "line": 42,
      "side": "RIGHT",
      "body": "![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)\n\nコメント本文"
    }
  ]
}
```

payloadはshell文字列へ展開せず、`gh-ops`に従って`--input`で渡す。

```bash
gh api --method POST \
  "repos/{base_repo}/pulls/{pr_number}/reviews" \
  --input "{review_payload_file}"
```

`APPROVE`や`REQUEST_CHANGES`を使わない。投稿後、返却されたreview IDでレビューとコメントを再取得し、件数、path、line、side、本文が承認内容と一致することを確認する。

```bash
gh api "repos/{base_repo}/pulls/{pr_number}/reviews/{review_id}"
gh api "repos/{base_repo}/pulls/{pr_number}/reviews/{review_id}/comments" --paginate
```
