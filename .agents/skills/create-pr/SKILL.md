---
name: create-pr
description: Pull Requestの作成・更新、Draft PR、Stacked PR、gh stack、ghコマンドによるPR作成を依頼されたときに使用する。
---

# Pull Request 作成

簡潔でレビュー可能な Draft PR を作成する。

**REQUIRED SUB-SKILL:** `gh` を使う前に `gh-ops` を読み、その認証・投稿・autolink・AI Generated バッジのルールに従う。

## Claude / Codex 共通の実行コンテキスト

このスキルと references は Claude / Codex の両方で使う。`SKILL.md` 内の参照パスはそのディレクトリ、references 内の相対リンクは各 reference のディレクトリを基準に解決する。Claude の Skill / Read、Codex のスキル読み込み・ファイル閲覧など、現在利用できる手段で全文を読む。

`active_worktree_path` が渡されていれば具体的な絶対パスを作業先とし、各コマンドの `workdir` または `git -C` に明示する。`worktree_isolation_required: true` なのにパスが未指定・不正なら本体へ戻らず停止する。PR 用 worktree を新規作成した場合はそのパスへ更新し、検証する。

## 簡潔に書く

本文は20行程度を目安に、実際の変更と検証結果を中心に書く。必須テンプレートや判断に必要な情報は行数のために省かない。対応 Issue があれば背景・原因・代替案の判断はリンク先を参照し、本文へ転載しない。Issue がなければ理解に必要な課題・原因を冒頭に短く補う。

- タイトルは変更の主題を1行で表し、括弧による長い補足を付けない
- 本文の先頭で「なぜ変えたか」と「何を変えたか」を1〜2文で示す
- 独立した変更点は5項目以内・各1〜2行を目安にし、一連の流れは短い段落で説明する。diffで分かる細部や変更ファイル一覧を転記しない
- 検証ごとに「何をどう確認し、結果どうだったか」を1〜2行で示す。Issue の完成条件・不変条件との対応を示し、全パス・ログ・判定表の全文は原文が必要な場合だけ載せる
- 補足はdiffを読むために必要なものを3項目以内・各1〜2行で書く。Issue に判断があればリンクし、未承認の Issue 編集やコメント投稿を本文作成の前提にしない
- 特定行だけに必要な補足は本文へ埋めず、ユーザーがセルフレビューコメントも依頼した場合に限り該当行へ投稿する

## 基本ルール

- PR はデフォルトで Draft として作成する。ユーザーが明示した場合だけ Ready for review にする
- タイトルと本文は、現在のリポジトリの規約・既存PR・PRテンプレートを優先する。規約がなければユーザーとの会話言語で簡潔に書く
- タイトルは変更の主題を1行で表し、Issue番号などのプレフィックスはリポジトリ規約で必須の場合だけ付ける
- 本文は「なぜ変えたか」と「何を変えたか」を先に示し、diffで分かる細部や試行錯誤を転記しない
- 未整理な検討過程や試行錯誤、個人環境の絶対パスをタイトル・本文・コメントへ記載しない
- Codex、ClaudeなどのエージェントセッションURLや内部実行URLを、タイトル・本文・コメント・コミットメッセージへ記載しない
- ユーザーのプロンプト履歴や内部指示をPR本文へ転載しない。リポジトリテンプレートが明示的に要求する場合は、公開してよい内容だけをユーザーへ確認する
- Issueとの関連が確認できる場合だけ本文冒頭に closing keyword を置く。推測でIssueを紐付けない
- Git履歴を書き換えるrebase、force push、ブランチ変更は、ユーザーの明示的な承認なしに行わない

## PRテンプレート

本文を作る前に、現在のリポジトリで追跡されているテンプレートを検索する。

```bash
git ls-files | rg -i \
  '^((\.github|docs)/)?pull_request_template\.md$|^\.github/pull_request_template/[^/]+\.md$'
```

次の優先順位で選択する。

1. ユーザーが指定したテンプレート
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. ルートの `PULL_REQUEST_TEMPLATE.md`
4. `docs/PULL_REQUEST_TEMPLATE.md`
5. `.github/PULL_REQUEST_TEMPLATE/*.md`

大文字・小文字の違いは同一として扱う。複数テンプレートがあり変更内容から選択できない場合は、本文を作る前にユーザーへ確認する。

テンプレートが見つかった場合:

- 見出し、チェック項目、HTMLコメントの指示に従う
- 必須セクションを削除・改名しない
- 該当しない項目はテンプレートの指示に従って `N/A` または理由を記載する
- AI Generated バッジをテンプレートの末尾へ追加する

テンプレートがない場合は、次のフォールバックを使う。

```markdown
{関連Issueを解決する場合のみ: Closes #123}

## 概要

{課題と変更の要点を1〜2文で記載}

## 変更内容

- {主要な変更}

## 確認方法

- {実行した確認と結果。未実行の場合はその理由}

## その他

- {レビュアーへ伝える必要がある補足。なければ「なし」}

![AI Generated](https://img.shields.io/badge/AI-Generated-blueviolet)
```

## 手順

### 1. リポジトリ、ブランチ、リモートの確認

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '{repository: .nameWithOwner, default_base: .defaultBranchRef.name}'
git status --short
branch=$(git branch --show-current)
git remote
git config --get "branch.${branch}.pushRemote"
git config --get remote.pushDefault
git config --get "branch.${branch}.remote"
```

- `branch` が空のdetached HEADでは停止し、ブランチ作成についてユーザーへ確認する
- デフォルトブランチ上では停止し、feature branchを作成してよいか確認する
- 未コミット変更がある場合は停止し、PRへ含める変更をcommitまたは退避する方針をユーザーへ確認する
- PRの作成先を `{base_repo}`、そのdefault branchを `{default_base}` とする。ユーザー指定がある場合は指定先を優先する
- `{base_repo}` を指す既存remoteを `{base_remote}` とする。見つからない場合はremoteを追加せず、ユーザーへ確認する
- push先 `{head_remote}` は `branch.<name>.pushRemote`、`remote.pushDefault`、`branch.<name>.remote`、単一remoteの順で解決する。値が `.`、存在しない、または複数候補で曖昧ならユーザーへ確認する
- `git remote get-url --push "{head_remote}"` でpush URLを確認し、そのGitHub repositoryとownerを `{head_repo}`、`{head_owner}` とする
- `{base_repo}`、`{base_remote}`、`{head_repo}`、`{head_remote}` を別の値として扱う。forkでも同一と仮定しない

### 2. 既存PRとbaseの確認

pushする前に、同じhead branchのopen PRを確認する。

`gh pr list --head`は`owner:branch`を受け付けないため、fork-awareな検索にはREST APIを使う。

```bash
gh api --method GET "repos/{base_repo}/pulls" \
  -f state=open \
  -f "head={head_owner}:$branch" \
  -f per_page=100 \
  --paginate --slurp \
  --jq 'flatten | map({number, title, draft, base: .base.ref, head: .head.ref, url: .html_url})'
```

- 既存PRがある場合は、そのPR番号・URL・base・Draft状態を提示する。依頼がそのPRの更新を含む場合は続行し、更新対象が曖昧な場合だけ確認する
- 既存PRがある場合の `{base}` は、ユーザーが変更を指示しない限り既存PRのbaseを維持する
- 新規PRではユーザー指定のbaseを最優先し、指定がなければデフォルトブランチを `{base}` とする

### 3. PR差分の確認

```bash
git fetch "{base_remote}" "{base}"
git diff --stat "{base_remote}/{base}...HEAD"
git log --oneline "{base_remote}/{base}..HEAD"
git diff "{base_remote}/{base}...HEAD"
```

PR本文はこの差分全体から作る。作業ツリーだけの差分や直近コミットだけを要約しない。

### 4. 関連Issueの確認

ユーザー指定、ブランチ名、コミットメッセージからIssue候補が明確な場合だけ確認する。

```bash
gh issue view "{issue_number}" --repo "{base_repo}" \
  --json number,title,state,url,body
```

Issue の本文を読み、完成条件や仕様判断がコメントにある場合は該当コメントも取得する。本文と検証結果をこの条件に照らして作る。

- このPRでopenなIssueを解決する場合は `Closes #<番号>` を本文冒頭に置く
- 参照だけ、closed、不在、関連が曖昧な場合はclosing keywordを付けない

### 5. 本文の作成

現在のセッションにユーザー添付の画像・動画（引き継いだ台帳を含む）がある場合は、[`references/media-attachments.md`](references/media-attachments.md) に従い、関連する添付と投稿先を確定する。承認済み添付の本文参照は補足欄内・AI Generated バッジより前に置き、対応する create / edit に `--attach` を渡す。添付なしの通常操作ではこの reference を読まない。

選択したリポジトリのテンプレート、またはフォールバックを一時ファイルへ展開する。

```bash
pr_body_file=$(mktemp "${TMPDIR:-/tmp}/create-pr-body.XXXXXX")
trap 'rm -f "$pr_body_file"' EXIT HUP INT TERM
```

本文にはバックティックをそのまま書き、不要なシェルエスケープを入れない。本文作成からPR操作までは同じshell sessionで行い、終了時に一時ファイルを必ず削除する。

### 6. push

upstreamの有無を確認し、既存設定を変更しない。

Stacked PRの場合はこの通常pushを実行せず、`references/stacked-pr.md`の`submit`または`link`にpushとbase設定を任せる。

```bash
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  git push "{head_remote}" "$branch"
else
  git push -u "{head_remote}" "$branch"
fi
```

pushが拒否された場合は原因を確認する。force pushは自動実行しない。

### 7. PRの作成または更新

新規PRの場合:

```bash
gh pr create \
  --draft \
  --repo "{base_repo}" \
  --base "{base}" \
  --head "{head_owner}:$branch" \
  --title "{変更の主題}" \
  --body-file "$pr_body_file"
```

ユーザーがReady for reviewを明示した場合だけ `--draft` を外す。

既存PRの更新をユーザーが承認した場合:

```bash
gh pr edit "{pr_number}" \
  --repo "{base_repo}" \
  {ユーザーがbase変更を明示した場合のみ: --base "{base}"} \
  --title "{変更の主題}" \
  --body-file "$pr_body_file"
```

既存PRのDraft / Ready状態は、ユーザーが状態変更を明示しない限り維持する。明示された場合だけ次を実行する。

```bash
# Ready指定
gh pr ready "{pr_number}" --repo "{base_repo}"

# Draft指定
gh pr ready "{pr_number}" --repo "{base_repo}" --undo
```

#### Stacked PR

- ユーザーが **Stacked PR** または **`gh stack`** を明示した場合だけ使う
- 親子関係やStack化を推測で適用しない
- [`references/stacked-pr.md`](references/stacked-pr.md)を全文読み、ローカル追跡stackと外部管理branchを区別して実行する
- stack操作に失敗しても通常の`git push` / `gh pr create`へ暗黙にフォールバックしない
- closing keywordは各PRが直接解決するIssueだけに付け、stack全体へ機械的に複製しない
- Ready for reviewの明示指定がある場合だけ`--open`を付ける

### 8. 作成結果の確認

```bash
gh pr view "{pr_number}" --repo "{base_repo}" \
  --json number,title,body,isDraft,baseRefName,headRefName,url,closingIssuesReferences
```

次を確認してPR URLを報告する。

- Draft状態とbase/headが意図どおり
- リポジトリのテンプレート構造を満たしている
- 必要なclosing keywordだけが含まれている
- 解決するIssueがある場合、`closingIssuesReferences`に期待するIssue番号がある
- 未整理な検討過程や試行錯誤、個人環境の絶対パスが含まれていない
- エージェントセッションURL、内部実行URL、プロンプト履歴が含まれていない
- AI Generated バッジが末尾にある

期待するIssueが`closingIssuesReferences`にない場合は、closing keywordの綴り、半角スペース、`#`、Issueのリポジトリを確認する。推測で別Issueへ付け替えない。

## セルフレビューコメント

ユーザーがPR作成に加えてセルフレビューコメントの投稿も明示した場合だけ行う。該当がなければ投稿しない。

- 対象は、意図的だが一見バグに見える実装の理由、または特定行に対応する現実的な故障シナリオ
- 一般的な変更説明、diffの言い換え、PR本文で足りる説明は投稿しない
- 投稿前に`ファイル:行`とコメント全文を一覧で提示する。対象と本文が承認済みなら再確認しない。未承認なら利用可能な質問UIまたは会話で投稿対象を選択してもらう
- 未承認の行コメントを読まないとPRを理解できない本文にしない。本文だけで変更と検証の要点が伝わる状態を保つ
- 選択されていないコメントを投稿しない
- 複数コメントは可能なら1つの`COMMENT`レビューにまとめ、通知を増幅させない
- severityバッジは付けず、各コメント冒頭にAI Generatedバッジを付ける
- [`references/self-review-comments.md`](references/self-review-comments.md)を全文読み、`gh-ops`の安全な本文受け渡しを使って投稿後に再取得する
