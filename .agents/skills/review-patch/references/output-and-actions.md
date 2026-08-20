# 出力・投稿・レビュー後アクション

最初に[`review-policy.md`](review-policy.md)を全文読む。

## 出力形式

会話とローカル成果物では`[critical]` / `[should]` / `[nits]` / `[ask]`を使う。GitHubへ投稿するときだけ対応する画像バッジへ変換する。

```markdown
## レビューサマリー

**変更の意図**: ...
**影響範囲**: ...

### 指摘一覧

| No. | ファイル:行 | タグ | 概要 | 対応 |
|---:|---|---|---|---|
| 1 | path:line | critical | ... | **対応推奨** — ... |

### 判定: APPROVE / REQUEST_CHANGES / COMMENT

### 指摘詳細

#### 1. [critical] `path:line` — 概要

- 問題: ...
- 発火条件: ...
- 根拠: ...
- 影響: ...
- 修正案: ...
- 対応判定: **対応推奨 / 対応不要 / 要確認** — ...
```

各指摘はタグ、変更後のファイル・行、問題、具体的な発火条件、コード上の根拠、影響、実行可能な修正案、対応判定を含む。`likely`を残す場合は未確認の前提を明記する。

指摘がゼロならAPPROVEとし、「指摘なし」、変更の意図、影響範囲を示す。投稿する必要がなければ投稿しない。

## GitHub投稿

CI等の明示された自動投稿コンテキストを除き、投稿前にサマリー、全指摘、eventを提示してユーザーの承認を得る。レビュー依頼だけを投稿許可と解釈しない。

- デフォルトeventは`COMMENT`
- `REQUEST_CHANGES` / `APPROVE`はユーザーが明示した場合だけ使う
- レビュー本文に`![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)`を付ける
- 各インラインコメントにタグの画像バッジを付ける
- `line`はdiff変更後の行、必要なら`side: "RIGHT"`、範囲は`start_line`と`line`を使う
- 複数コメントは1件のreview payloadとして投稿する
- payloadは一時ファイルへ安全に生成するか、構造化入力として渡す。ユーザー由来文字列を固定heredocへ展開しない
- 投稿直前にPRの`headRefOid`を再取得し、レビューした`head_sha`と一致しなければ投稿を停止して再レビューの要否を確認する
- review payloadの`commit_id`にはレビューした`head_sha`を指定する
- 投稿後はreviewsとcommentsを再取得し、event、本文、path、lineを照合する

GitHub操作の詳細は`gh-ops`に従う。

## レビュー後アクション

| コンテキスト | アクション |
|---|---|
| 明示されたCI自動レビュー | 構成済みの権限・eventで投稿 |
| authorが現在のユーザー、またはローカル差分 | 結果を提示し、修正対象を`all / 番号 / none`で確認 |
| 他メンバーのPR | 結果を提示し、GitHub投稿を確認 |

確認前にファイルを変更しない。選択された指摘だけを修正し、プロジェクト既定の検証手順を確認して実行する。commit、push、投稿はそれぞれ明示的な依頼・承認がある場合だけ行う。

## PR用worktreeのcleanup

レビューのみでworktreeがcleanなら、成果物がworktree外にあることを確認してから専用worktreeと一時refを削除する。修正でdirtyならforce removeせず、pathを報告して保存・転送方法をユーザーへ確認する。本体checkoutは変更しない。
