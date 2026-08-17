# Stacked PR

`create-pr`でStacked PRまたは`gh stack`を明示された場合だけ、この手順を使う。

## 1. capability確認

まずローカルの実際のCLIを確認する。

```bash
gh --version
git --version
gh stack --help
```

`gh stack`が利用できなければ、公式extensionの要件と導入コマンドを`gh extension`のhelpまたは公式資料で確認する。自動インストールせず、導入してよいかユーザーへ確認する。導入または再確認に失敗したら停止し、通常のPR作成へ暗黙にフォールバックしない。

各サブコマンドのフラグは推測せず、実行前に次を確認する。

```bash
gh stack init --help
gh stack add --help
gh stack rebase --help
gh stack submit --help
gh stack link --help
gh stack view --help
```

## 2. モード選択

| 状態 | コマンド |
|---|---|
| gh-stackでローカル追跡するbranch列を新規作成・採用する | `init` / `add` / `rebase` / `submit` |
| 既存branchやPRを別ツールで管理し、GitHub上だけStack化する | `link` |

ユーザーの既存branch管理方式を勝手に変更しない。判断できなければ、branch列をgh-stackのローカル追跡へ採用するか、GitHub上だけlinkするか確認する。

## 3. 全branchのpreflight

stackを変更する前に、最下層から最上層まで全head branchについてopen PRを確認する。

`gh pr list --head`は`owner:branch`を受け付けないため、各branchをREST APIでfork-awareに検索する。

```bash
gh api --method GET "repos/{base_repo}/pulls" \
  -f state=open \
  -f "head={head_owner}:{branch}" \
  -f per_page=100 \
  --paginate --slurp \
  --jq 'flatten | map({number, title, draft, base: .base.ref, head: .head.ref, url: .html_url})'
```

既存PRがあれば、各PRの番号、URL、現在のbase、Draft状態と、stack操作で変更される予定のbase・状態を提示する。ユーザーが更新を承認するまで`init` / `rebase` / `submit` / `link`を実行しない。

`--open`の有無は新規PRの既定状態を決めるだけで、既存PRの状態を必ず希望値へ戻すとは仮定しない。stack操作後、ユーザーが明示した状態と異なる既存PRだけを`gh pr ready`または`gh pr ready --undo`で揃え、再取得する。

## 4. ローカル追跡stack

最下層から最上層の順でbranchを扱う。既存branch列を採用する場合は、各親子について実際の履歴を確認する。

```bash
git merge-base --is-ancestor "{parent}" "{child}"
```

関係が確認できなければ、推測でstackへ採用しない。

新規または既存branch列を初期化する。

```bash
gh stack init --base "{base}" "{bottom_branch}" "{next_branch}" "{top_branch}"
```

作業を積み上げながら層を追加する場合は、各変更をcommitした後に`gh stack add "{next_branch}"`を使う。ブランチ作成、commit、履歴書き換えが新たに必要なら、その操作についてユーザーの承認範囲を確認する。

手動rebase後や既存branch採用後は、submit前にローカルメタデータと親子関係を同期・確認する。

```bash
gh stack rebase --no-trunk --remote "{head_remote}"
gh stack view --json
```

非対話環境ではstack全体をsubmitする。新規PRをDraftにするため、Ready指定がない限り`--open`を付けない。

```bash
gh stack submit --auto --remote "{head_remote}"
```

`submit`がbranchのpush、PR作成、base設定を行うため、事前に同じbranchへ通常の`git push`や`gh pr create`を重ねない。

## 5. 外部管理branch / PRのlink

親から子の順に、branch、PR番号、PR URLを渡す。

```bash
gh stack link \
  --base "{base}" \
  --remote "{head_remote}" \
  {Ready指定時のみ: --open} \
  "{bottom_branch_or_pr}" \
  "{next_branch_or_pr}" \
  "{top_branch_or_pr}"
```

`link`がbranchのpush、未作成PRの作成、base設定を行う。事前に同じ操作を重ねない。

## 6. 各PRの本文を仕上げる

`--auto`や`link`が生成したタイトル・空のテンプレート本文を完成扱いしない。各branchのopen PRをpreflightと同じREST APIでfork-awareに特定する。

```bash
gh api --method GET "repos/{base_repo}/pulls" \
  -f state=open \
  -f "head={head_owner}:{branch}" \
  -f per_page=100 \
  --paginate --slurp \
  --jq 'flatten | map({number, title, draft, base: .base.ref, head: .head.ref, url: .html_url})'
```

各PRについて実際の`baseRefName` / `headRefName`を取得し、`gh pr diff`でそのPR固有の差分を読む。通常PR手順の`...HEAD`をstack全層へ使い回さない。

```bash
gh pr diff "{pr_number}" --repo "{base_repo}"
```

この差分からタイトルと本文を作り、PRごとに別の一時body fileを使って更新する。

```bash
gh pr edit "{pr_number}" \
  --repo "{base_repo}" \
  --title "{その層の変更の主題}" \
  --body-file "{そのPR専用のbody_file}"
```

テンプレート、簡潔さ、確認結果、AI Generatedバッジの規則は通常PRと同じとする。

closing keywordは、その層が直接解決するopen Issueだけに付ける。同じIssueをstack全体へ複製しない。

1つのIssueがstack全体で初めて解決する場合、どのPRが解決を完成させるかを推測せずユーザーへ確認する。直接解決するPRを定められなければclosing keywordを付けない。非default branchをbaseにするPRではGitHubの自動close判定が保留され得るため、`closingIssuesReferences`が空であることだけを理由にkeywordを別層へ複製しない。

## 7. stack全体を検証する

```bash
gh stack view --json
gh pr view "{pr_number}" --repo "{base_repo}" \
  --json number,title,body,isDraft,baseRefName,headRefName,url,closingIssuesReferences
```

すべてのPRについて次を確認する。

- 新規PRはReady指定がなければDraftである。既存PRはpreflightでユーザーと合意したDraft / Ready状態である
- 最下層は`{base}`、以降は直下の親branchをbaseにしている
- 各本文がその層固有の差分だけを説明している
- 選択したPRテンプレートの必須構造を満たしている
- closing keywordが、その層が直接解決するIssueだけを示している
- default branchをbaseにするPRでは、期待するIssueが`closingIssuesReferences`にある。非default baseではkeyword本文を確認し、自動close判定が保留中ならその旨を報告する
- AI Generatedバッジが末尾にある
- エージェントセッションURL、内部実行URL、プロンプト履歴、個人環境の絶対パスを含まない

1つでも満たさなければ完了扱いにせず、変更操作の承認範囲内で修正して再取得する。
