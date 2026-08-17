---
name: review-patch-crosscheck
description: 複数の独立レビューを突き合わせる、徹底的な多視点コードレビューを依頼されたときに使用する。
---

# Review Patch Crosscheck

同じ差分を4チャネルで独立に静的レビューし、全チャネル完了後に初めて結果を統合する。

| チャネル | 実行主体 | 役割 |
|---|---|---|
| rules-agent | サブエージェント + `review-patch` | プロジェクト規約を踏まえたレビュー |
| senior-codex | `codex exec review` | シニアエンジニア視点のネイティブレビュー |
| adversarial-codex | `codex exec` | 壊し方から探す敵対的レビュー |
| rules-codex | `codex exec` + `review-patch` | Codexによるプロジェクト規約準拠レビュー |

チャネル間でプロンプト、途中経過、指摘候補を共有しない。相互参照はマージ時に限る。通常レビューより時間とトークンを使うため、徹底レビューにだけ適用する。

**REQUIRED SUB-SKILL:** PRを対象にする場合や`gh`を使う場合は、`gh-ops`を読み、そのルールに従う。

## 前提

開始前に次を確認する。

```bash
command -v codex
codex --version
```

- Codex CLI 0.144.0以降
- 前提を満たさなければ実行せず、不足条件を報告する
- モデルとeffortは全CodexチャネルへCLIフラグで明示する
- Codex 3チャネルのsandbox、approval、セッション永続化は実行テンプレートで制御し、ユーザー設定に依存しない

## 引数

```text
/review-patch-crosscheck [PR番号|PR URL] [--target staged|working|pr|pr:{base}] [--prefix NAME] [--model MODEL] [--effort EFFORT] [追加レビュー指示]
```

| オプション | デフォルト | 説明 |
|---|---|---|
| `--target` | `staged` | ローカルレビューの差分範囲 |
| `--prefix` | `review` | `{workdir}`直下に置く出力ファイルの接頭辞 |
| `--model` | `gpt-5.6-sol` | Codex 3チャネルのモデル |
| `--effort` | `medium` | `medium` / `high` / `xhigh` / `max`。固定4チャネルを保つため`ultra`は使わない |

引数は左から走査する。PR番号または同一リポジトリのPR URLは最大1個、各オプションは最大1個とする。重複、未知オプション、値不足、不正値は実行前にエラーにする。PR指定と`--target`は排他とする。`prefix`は`[A-Za-z0-9._-]+`、modelは`[A-Za-z0-9][A-Za-z0-9._:/-]*`に制限し、改行や制御文字を含む値を拒否する。baseは`git check-ref-format --branch`で検証する。

オプションとPR指定以外の残りは追加レビュー指示として4チャネルへ同一内容を渡す。ただし静的レビュー契約に反する指示は拒否する。ユーザー指定なしにmodelやeffortを変更しない。

## レビュー対象

ベースブランチは`git symbolic-ref refs/remotes/origin/HEAD`から解決し、得られなければ`main`とする。

| 指定 | 差分コマンド |
|---|---|
| `staged` | `git diff --cached` |
| `working` | `git diff HEAD` |
| `pr` | `git diff {merge_base_sha}...HEAD` |
| `pr:{base}` | `git diff {merge_base_sha}...HEAD` |
| PR番号 / URL | `git diff {merge_base_sha}...HEAD` |

`pr` / `pr:{base}`では、検証済みbase refをshellへ埋め込まず、gitコマンドの引数として渡してmerge-baseを先に計算する。結果が完全なcommit SHAであることを検証して`{merge_base_sha}`へ入れる。

PR番号またはURL指定時は`gh-ops`を読み、最初は`baseRefName`と`headRefOid`だけを取得する。baseをfetchし、GitHubの`refs/pull/{PR}/head`を一時refへfetchして、期待する`headRefOid`と一致することを確認する。そのSHAをdetached HEADとして新しい専用worktreeへ展開する。既存ローカルbranchや`origin/{head}`を再利用せず、fork PRでもbase repositoryのpull refから取得する。本体checkoutがdirtyでもstash、reset、checkout、branch変更を行わない。

PR本文、linked issue、コミットメッセージ、既存レビューはこの時点では読まない。以降の`{workdir}`は専用worktreeの絶対パスとする。

ローカル指定の`{workdir}`は、具体的な絶対パスで引き渡されたworktreeがあればそのパス、なければ`git rev-parse --show-toplevel`とする。変数名、相対パス、過去のシェル状態から補完しない。

### 隔離不変条件

セットアップ後、マージ前、修正前に検査する。失敗時は本体checkoutへフォールバックせず終了する。

- `git -C "{workdir}" rev-parse --show-toplevel`の結果が`{workdir}`と一致する
- `{workdir}`が`git worktree list --porcelain`に存在する
- PR指定または呼び出し元がworktree隔離必須とした場合、`{workdir}`は`dirname "$(git -C "{workdir}" rev-parse --path-format=absolute --git-common-dir)"`と異なる
- PR指定時は`git -C "{workdir}" rev-parse HEAD`が取得済み`headRefOid`と一致する
- `{workdir}`、成果物パス、CLIへ渡すその他のパスはcanonicalな絶対パスとし、shell sourceへ直接埋め込む場合は`[A-Za-z0-9._/ -]+`に収まらなければ停止する

## 出力

ローカル対象では`{artifact_dir}`を`{workdir}`とする。PR番号またはURL指定では、worktree削除後も結果を保持できるよう、`mktemp -d "${TMPDIR:-/tmp}/review-patch-crosscheck.XXXXXX"`でworktree外に専用`{artifact_dir}`を作る。

既存ファイルと衝突しない整数`{seq}`を実行ごとに採番する。並行実行による衝突を避けるため、canonical repository pathとprefixを`shasum`でhex keyへ変換し、`/tmp`配下の`{key}-{seq}.lock` directoryを`mkdir`で原子的に予約する。取得できなければ次のseqを試し、完了時に自分が作成したlockだけを削除する。異常終了でlockが残っても削除せず、次のseqを使う。

```text
{artifact_dir}/{prefix}-rules-agent_{seq}.md
{artifact_dir}/{prefix}-senior-codex_{seq}.md
{artifact_dir}/{prefix}-adversarial-codex_{seq}.md
{artifact_dir}/{prefix}-rules-codex_{seq}.md
{artifact_dir}/{prefix}-merged_{seq}.md
{artifact_dir}/{prefix}-timing_{seq}.log
```

各チャネルの開始・終了epoch秒をtiming logへ`channel,attempt,start,end,result`形式で追記する。`result`はexit code、`timeout`、またはサブエージェントの完了状態とする。並列追記は1行単位で行う。

`codex exec review`は`-C`を受け付けないため、`cd "{workdir}" && codex exec review ...`とする。`--uncommitted` / `--base` / `--commit`はPROMPTによる対象指定と併用しない。通常の`codex exec`には`-C "{workdir}"`を使う。

## 事前処理の禁止

4チャネル起動前に許される対象確認は、差分コマンドへ`--stat`を付けた空チェックだけとする。diff本文、変更ファイル、PR本文、linked issue、コミットメッセージ、既存レビューを読まず、内容分析、関連ルールの選別、レビュー観点の取捨選択を行わない。空ならチャネルを起動せず「レビュー対象なし」と終了する。

## 手順

### 1. セットアップ

1. 引数を厳密にパースし、前提を検証する。
2. PR指定時は専用worktreeを作成する。
3. `{workdir}`を確定し、隔離不変条件を検査する。
4. merge-base SHA、差分コマンド、`{artifact_dir}`、絶対出力パス、`{seq}`を確定する。
5. `--stat`だけで空チェックする。

### 2. 4チャネルを同時起動

[`references/channel-prompts.md`](references/channel-prompts.md)を全文読み、テンプレートを具体値で展開する。起動前チェックを通した後、同じターンでrules-agentをバックグラウンド起動し、Codex 3コマンドもそれぞれバックグラウンド起動する。逐次実行しない。

起動直後に次の表を提示し、待機中は状態と経過秒を更新する。

```markdown
| チャネル | 状態 | 経過秒 |
|---|---|---:|
| rules-agent | running | - |
| senior-codex | running | - |
| adversarial-codex | running | - |
| rules-codex | running | - |
```

各チャネルの制限時間は15分とし、超過したチャネルは終了させてtimeout扱いにする。1チャネルが失敗しても他を止めない。終了後に失敗チャネルだけ1回再試行する。再試行は`{canonical_output}.attempt-2`へ出力し、検証に通った場合だけcanonical outputとして採用する。初回の部分出力や違反出力を上書き・採用しない。再失敗時は理由を明記し、成功したチャネルだけで暫定マージする。次も失敗として扱う。

- 出力が空
- 期待フォーマットを満たさない
- 静的レビュー契約への違反を観測した
- 指定した差分以外をレビュー対象にした
- 15分以内に終了しない

禁止コマンドの実行結果はレビュー根拠に採用しない。

### 3. マージ

全チャネル完了後に出力を初めて読む。PR指定時はここでPR本文、linked issue、コミットメッセージ、既存レビューを取得する。変更意図を知っていれば解消する`ask`、作者が回答済みの論点、既存指摘との重複を除外する。

`review-patch`の出力規則とタグ判定を読み、各候補について差分起因性、対象外ファイル、根拠、actionable性を再検証する。

- 表現が異なる同一論点は、発火条件・影響・修正方針でまとめる。行番号だけの違いでは別件にしない
- 各指摘には検出した全チャネルを記録する
- 一致数は調査順序であり、正しさの投票ではない
- 同じモデル由来の相関誤りを考慮し、到達可能な発火条件とコード上のevidenceで判断する
- 同一箇所に複数観点が交差する場合は複合影響を検討し、必要ならseverityを上げる

| 独立チャネル一致数 | 扱い |
|---:|---|
| 3〜4 | 最優先でevidenceを検証 |
| 2 | 高優先でevidenceを検証 |
| 1 | 固有指摘として同じ基準で検証 |

adversarialの`Critical` / `Warning` / `Info`やnative reviewのseverityは機械変換せず、`review-patch`の判定基準で`critical` / `should` / `nits` / `ask`を決め直す。

`{prefix}-merged_{seq}.md`へ次の構造で全文を書き、同じ全文を省略・要約せず会話へ提示する。

```markdown
## レビューサマリー

**変更の意図**: ...
**影響範囲**: ...

### 指摘一覧

| No. | ファイル:行 | タグ | 概要 | 指摘元 | 対応 |
|---:|---|---|---|---|---|
| 1 | path:line | critical | ... | rules-agent, senior-codex | **対応推奨** — ... |

### 判定: APPROVE / REQUEST_CHANGES / COMMENT

検証: 静的確認のみ（テスト・lint・build未実行）

### 指摘詳細

#### 1. [critical] `path:line` — 概要

- 問題: ...
- 発火条件: ...
- 根拠: ...
- 影響: ...
- 修正案: ...
- 対応判定: ...
```

各指摘の詳細には、問題、具体的な発火条件、根拠、影響、修正案、対応判定を含める。指摘ゼロならAPPROVEとし、「指摘なし」、変更意図、影響範囲を記載する。

会話とローカル成果物では`[critical]` / `[should]` / `[nits]` / `[ask]`のテキストバッジを使う。GitHubへ投稿するときだけ、`review-patch`の規則に従って対応する画像バッジへ変換する。

### 4. 結果提示と修正

PR指定時は`gh pr view {PR} --json author`でauthorを確認する。他メンバーのPRなら修正フローに入らず、`review-patch`のGitHub投稿フローへ進む。投稿は必ず事前確認を取り、本文から「指摘元」列とレビュー体制の説明を除く。

authorが自分、またはローカル指定なら次だけを確認する。

```text
修正しますか？（all / 番号指定 / none）
```

確認前にファイルを変更しない。選択された指摘だけ対象ファイルを改めて読み、修正する。検証は`AGENTS.md`、プロジェクト文書、task runner定義を確認し、対象に対応する既定タスクを優先する。直接コマンドしかない場合は、変更に対応する最小のlint / test / build / codegenを実行する。

PR指定でレビューだけを行った場合は、成果物が`{artifact_dir}`に存在することを確認してから専用worktreeを削除する。修正によりworktreeがdirtyになった場合は削除・force removeせず、変更の保存または転送方法についてユーザーへ確認し、worktree pathを報告する。

### 5. 完了報告

対応した指摘、スキップした指摘と理由、検証結果、各チャネルの経過秒と生存した固有指摘数を報告する。コミット、push、GitHub投稿はユーザーが明示的に依頼・承認した場合だけ行う。
