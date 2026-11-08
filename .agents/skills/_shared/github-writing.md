# GitHub 操作・投稿の共通規約

GitHub の情報取得・変更前に全文を読む。投稿・編集前には文章、本文の受け渡し、添付の節も適用する。操作対象・投稿内容について既に得た明示的な承認は引き継ぎ、同じ確認を繰り返さない。

## 基本方針

- 実行対象のリポジトリを最初に確認する。カレントリポジトリ以外を操作するときは `--repo OWNER/REPO` を明示する。
- 読み取りでは、人間向け表示の解析を避け、利用可能なら `--json` と `--jq` を使う。
- フラグや出力項目が不明な場合は、推測せず `gh <command> --help` で確認する。
- `gh` の実行前に `gh auth status` で認証状態を確認しない。目的の `gh` コマンドを直接実行し、認証エラーになった場合にだけ、[認証復旧](../setup-workspace/references/gh-auth.md)へフォールバックする。
- 作成・編集・コメント・レビュー・close・merge・delete・workflow dispatch など、GitHub の状態を変える操作は、ユーザーが依頼した範囲だけ実行する。
- 変更操作の後は対応する `view`、`list`、`api` などで結果を再取得し、反映内容を確認する。
- token、credential、認証ヘッダをコマンド出力・ログ・一時ファイル・会話へ露出させない。

## クイックリファレンス

| 目的 | コマンド例 |
|---|---|
| リポジトリ確認 | `gh repo view --json nameWithOwner,url,defaultBranchRef` |
| Issue の取得 | `gh issue view <番号> --json number,title,body,state,url` |
| PR の取得 | `gh pr view <番号> --json number,title,body,state,url,headRefName,baseRefName` |
| Actions の確認 | `gh run list` / `gh run view <ID> --log-failed` |
| REST / GraphQL API | `gh api ...` / `gh api graphql ...` |

## 構造化データとページネーション

```bash
gh pr view 123 --json number,title,state,url --jq '{number, title, state, url}'
```

一覧 API では取りこぼしを避けるため、複数ページになり得る場合は `--paginate` を使う。レスポンスを1つの配列へまとめる必要がある場合は `--slurp` も使う。

```bash
gh api --paginate 'repos/{owner}/{repo}/issues?state=all&per_page=100'
```

## 変更操作

高影響な操作（PR の merge、Issue/PR の close、Release の削除、workflow dispatch など）は、ユーザーの明示的な依頼がある場合にだけ実行する。

## autolink の回避

GitHub は本文中の `#数字` を自動的に Issue/PR へのリンクに変換する。**意図しないリンクを防ぐため、`#数字` は実際の Issue/PR を参照する場合にのみ使う。**

順序・連番・ラベルとして番号を振りたい場合は `#` を付けない:

| 避けるべき表記 | OK |
|---|---|
| `問題 #1` / `sub-issue #2` | `問題 1` / `sub-issue 2` |
| `| # | 問題 | 影響 |`（テーブルヘッダ）| `| No. | 問題 | 影響 |` |
| `ステップ #3 で失敗` | `ステップ 3 で失敗` |

Closing keywords（`Closes #1234` 等）や意図的な Issue/PR 参照は autolink 回避の対象外。

## Closing keywords

PR 本文で Issue との紐付けに使うキーワード。

| 用途 | キーワード | Development 自動紐付け | マージ時 Issue クローズ |
|---|---|---|---|
| この PR で Issue を解決する | `Closes` / `Fixes` / `Resolves` | ○ | ○ |
| 参照のみ（クローズしない） | `Refs` | × | × |

- closing keyword は PR 本文の冒頭に記載する（`Closes #1234`）。同じ Issue 番号への `#` 参照は初出と機能的参照に限り、見出しや連番には使わない
- 参照のみで Development に紐付けたい場合は、closing keyword は使わず、PR 作成後に `gh pr edit` や Web UI から手動でリンクする

## AI Generated バッジ

AI エージェントが作成・投稿するコンテンツには `![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)` バッジを付与する。

- **PR 本文**: 末尾に付与
- **レビューコメント・返信**: 本文冒頭に付与

## コンテンツの渡し方

### 本文を受け取る create / edit / comment

本文は一時ファイルに書き出し、`--body-file` で渡す。`--body "..."` はシェル展開や引用符の影響で Markdown が壊れやすい。

- **本文中のバックティックを絶対にエスケープしない**（`` \` `` と書かない）
- 投稿後、エスケープ済みバックティックが残っていないか確認する:
  ```bash
  gh pr view <番号> --json body -q .body | grep -c '\\`'
  ```

### `gh api`

`-f` オプションは感嘆符をバックスラッシュエスケープするため、`--input` で JSON を stdin 経由で渡す。

## 文章の構成

要点と短い理由を先に置き、根拠・調査資料を後ろへ置く。因果や再現手順は番号付きリスト、比較は表、順序のない独立した要点は箇条書き、完了条件はチェックリストを使う。形式を埋めるためだけに項目を増やさない。

機能・責務を主語にし、長いパスや内部識別子を文中に連ねない。ログは判断に原文が必要な部分だけを載せ、長い原文は要約の後ろの details に置く。結論、重要な制約、判断を妨げる未確認事項は折りたたまない。

個人のローカル絶対パスはユーザー名を伏せるか相対パスにする。エージェントのセッション URL、内部実行 URL、非公開の指示を本文・コメント・コミットメッセージへ記載しない。

## 添付

セッション添付やローカルの画像・動画を投稿する場合だけ [添付メディア](media-attachments.md) を全文読む。レビュー投稿の承認を別コメントや添付の承認へ拡張しない。
