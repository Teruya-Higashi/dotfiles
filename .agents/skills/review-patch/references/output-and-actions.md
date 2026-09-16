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

CI等の明示された自動投稿コンテキストを除き、投稿前にサマリー、全指摘、eventを提示してユーザーの承認を得る。レビュー依頼だけを投稿許可と解釈しない。`--post`指定時はフラグ指定を承認済みとみなし、確認なしで投稿する。

- デフォルトeventは`COMMENT`
- `REQUEST_CHANGES` / `APPROVE`はユーザーが明示した場合だけ使う
- レビュー本文に`![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)`を付ける
- 各インラインコメントにタグの画像バッジを付ける
- `line`はdiff変更後の行、必要なら`side: "RIGHT"`、範囲は`start_line`と`line`を使う
- 複数コメントは1件のreview payloadとして投稿する
- payloadは一時ファイルへ安全に生成するか、構造化入力として渡す。ユーザー由来文字列を固定heredocへ展開しない
- 投稿直前にPRのstate、baseRefName、headRefOidを再取得し、base refを新しい一意temporary refへfetchする。OPEN、base名不変、headRefOidがレビューした`head_sha`、`merge-base(live base tip, head_sha)`がレビュー時の`base_sha`と一致する場合だけ投稿し、取得・fetch失敗または不一致では停止して最新snapshotを再レビューする
- review payloadの`commit_id`にはレビューした`head_sha`を指定する
- 投稿後はreviewsとcommentsを再取得し、event、本文、path、lineを照合する

GitHub操作の詳細は`gh-ops`に従う。サマリーの判定は参考情報であり、投稿 API の event とは独立とする。

現在のセッションにユーザー添付の画像・動画（過去ターンの台帳登録分を含む）がある場合は [`../../create-pr/references/media-attachments.md`](../../create-pr/references/media-attachments.md) を読む。レビュー API は `--attach` 非対応なので、関連添付は承認された companion comment を1件投稿し、その URL をレビュー本文へ記載する。`--post` はレビュー指摘の投稿承認であり、添付や別コメントの追加を自動承認しない。既存の明示承認は引き継ぎ、部分成功・再試行では同じ添付コメントを重複作成しない。`--local` では GitHub へ添付しない。

## ローカル媒体への投稿（`--local`）

`--local`では[`local-review-mode.md`](local-review-mode.md)を全文読み、正本eventにだけ投稿する。Phase 3のフィルタリングとサマリー提示が終わるまで、finding生成・既存finding取得・投稿を行わない。

- `--post`なし: サマリーと全指摘を提示し、承認後だけ投稿する
- `--post`あり: フラグ指定を承認済みとして投稿する
- 投稿後: helperの`reduce`を再実行し、review-runとthread状態を照合する
- locator: `local-review-mode.md`の書式でreview ID、review directory、返信コマンドを提示する
- 書込み失敗時: manifestを変更せず、helperのJSON出力とexit codeを報告する

## レビュー後アクション

| コンテキスト | アクション |
|---|---|
| 明示されたCI自動レビュー | 構成済みの権限・eventで投稿 |
| authorが現在のユーザー、またはローカル差分 | 結果を提示し、修正対象を`all / 番号 / none`で確認 |
| 他メンバーのPR | 結果を提示し、GitHub投稿を確認 |
| `--local` | 結果を提示し、正本eventへの投稿を確認。`--post`なら確認を省略 |

`--fix`指定時は修正確認を行わず、critical / shouldを選択済みとして修正する。それ以外は確認前にファイルを変更しない。選択された指摘だけを修正し、`AGENTS.md` / `CLAUDE.md` と task runner 定義からプロジェクト既定の検証手順を確認して実行する。対象に対応する `mise run` 等のタスクがあれば優先し、存在しなければ最小の直接コマンドを使う。

- commit前にリポジトリのgit/commit規約を読む
- 選択された指摘への対応hunkだけをstageする。既存unstaged hunkと安全に分離できなければcommit前に停止する
- PR以外のローカル差分は検証後にcommitし、既存変更を巻き込まずpushしない
- PR対象は自分のPRだけ修正する。`--local`なしは同一repositoryだけcommit + pushし、forkでは`--fix`を拒否する。PR + `--local`は同一repositoryならpushし、forkならcommitまでで止める
- commit、push、投稿は明示的な依頼・承認がある場合だけ行う。`--fix` / `--post`は該当操作の承認とみなす

## PR用worktreeのcleanup

レビューのみでworktreeがcleanなら、成果物がworktree外にあることを確認してから専用worktreeと一時refを削除する。修正でdirtyならforce removeせず、pathを報告して保存・転送方法をユーザーへ確認する。Serena 等を切り替えた場合は削除前に元の絶対パスへ戻す。本体checkoutは変更しない。PR番号 + `--local`ではactive manifestがworktreeを返信対応に使うため削除せず、`local-review-mode.md`のworktree寿命に従う。
