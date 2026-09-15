---
name: review-patch-crosscheck
description: Use when 徹底的な多視点コードレビュー、ship前の最終レビュー、または複数の独立レビューの突き合わせを依頼されたとき。
---

# Review Patch Crosscheck

同じ差分を4チャネルで独立に静的レビューし、全チャネル完了後に初めて結果を統合する。

| チャネル | 実行主体 | 役割 |
|---|---|---|
| rules-agent | サブエージェント + `review-patch` | プロジェクト規約を踏まえたレビュー |
| senior-codex | `codex exec review` | シニアエンジニア視点のネイティブレビュー |
| adversarial-codex | `codex exec` | 壊し方から探す敵対的レビュー |
| rules-codex | `codex exec` + `review-patch` | Codexによるプロジェクト規約準拠レビュー |

チャネル間でプロンプト、途中経過、指摘候補を共有せず、相互参照はマージ時に限る。

**REQUIRED SUB-SKILL:** PRを対象にする場合や`gh`を使う場合は、`gh-ops`を読み、そのルールに従う。

## Claude / Codex 共通の実行コンテキスト

このスキルと references は Claude / Codex の両方で使う。`SKILL.md` 内の参照パスはそのディレクトリ、references 内の相対リンクは各 reference のディレクトリを基準に解決する。Claude の Skill / Read、Codex のスキル読み込み・ファイル閲覧など、現在利用できる手段で全文を読む。

`active_worktree_path` が渡されていれば具体的な絶対パスを作業先とし、各コマンドの `workdir` または `git -C` に明示する。`worktree_isolation_required: true` なのにパスが未指定・不正なら本体へ戻らず停止する。PR 用 worktree を新規作成した場合はそのパスへ更新し、検証する。

## 前提

開始前に`command -v codex`と`codex --version`でCodex CLI 0.144.0以降を確認し、不足時は実行しない。モデル、effort、sandbox、approval、セッション永続化は3チャネルのCLIフラグで固定し、ユーザー設定に依存しない。

## 引数

```text
/review-patch-crosscheck [PR番号|PR URL] [--watch] [--fix] [--post] [--local] [--target staged|working|pr|pr:{base}] [--prefix NAME] [--model MODEL] [--agent-model MODEL] [--claude-model MODEL] [--effort EFFORT] [追加レビュー指示]
```

| オプション | デフォルト | 説明 |
|---|---|---|
| `--target` | `pr` | ローカルレビューの差分範囲 |
| `--prefix` | `review` | `{artifact_dir}`直下に置く成果物ファイル名の接頭辞 |
| `--model` | `gpt-5.6-sol` | Codex 3チャネルのモデル |
| `--agent-model` | 親セッションを継承 | rules-agent のモデル。実行環境が受理する名前を指定 |
| `--claude-model` | なし | Claude 上での `--agent-model` の別名。Codex 上では拒否 |
| `--effort` | `medium` | `medium` / `high` / `xhigh` / `max`。固定4チャネルを保つため`ultra`は使わない |
| `--watch` | なし | PRはコミット追加、`--local`のローカル対象は安定したdiff fingerprintとconsumer replyを監視して再レビューする |
| `--fix` | なし | critical / shouldを確認なしで修正する。PR以外はcommitまで、自分の同一repository PRはcommit + pushする。PR + `--local`のforkだけcommit止まりを許す |
| `--post` | なし | 検証済み指摘を事前確認なしで選択した媒体へ投稿する |
| `--local` | なし | 投稿先をGitHubではなくローカルのreview directory（正本event）にする。PR番号との併用ではPR用worktreeをtargetにする |

`--agent-model` と `--claude-model` は併用不可。未指定時は親のモデルを継承する。指定時は利用可能なモデルと起動ツールの引数を確認し、不正・非対応なら起動前に拒否する。Codex 3チャネルの `--model` と混同しない。

引数は左から走査する。PR番号または同一リポジトリのPR URLは最大1個、各オプションは最大1個とする。重複、未知オプション、値不足、不正値は実行前にエラーにする。PR指定と`--target`は排他とする。`prefix`は`[A-Za-z0-9._-]+`、modelは`[A-Za-z0-9][A-Za-z0-9._:/-]*`に制限し、改行や制御文字を含む値を拒否する。baseは`git check-ref-format --branch`で検証する。

PR・`--target` の指定がなければ `pr` に正規化してから manifest と watch の対象を確定する。

`--local`なしの`--post` / `--watch`はPR指定必須。`--local`はPR指定の有無を問わず`--watch` / `--post`と併用できる。PR + `--local`ではPR用worktreeを`{workdir}`、targetを`pr-number:{n}`とし、GitHubへレビュー投稿しない。

- `--local`では[`../review-patch/references/local-review-mode.md`](../review-patch/references/local-review-mode.md)を全文読み、producerを`review-patch-crosscheck`としてmanifestを確定する
- `--watch`では[`references/watch-mode.md`](references/watch-mode.md)を全文読む
- PRの`--fix`はauthorが自分以外なら拒否する
- `--fix --post`は修正を先に行い、解消した指摘を投稿しない

PR以外への`--fix`はdetached HEADでは拒否し、修正・検証・commitまで行ってpushしない。PR対象は自分のPRだけ修正し、他人のPRでは拒否する。`--local`なしは同一repositoryだけcommit + pushし、forkでは拒否する。PR + `--local`は同一repositoryならpushし、forkならcommitまでで止める。

オプションとPR指定以外の残りは追加レビュー指示として4チャネルとboundary-followupへ同一内容を渡す。ただし静的レビュー契約に反する指示は拒否する。ユーザー指定なしにmodelやeffortを変更しない。

## レビュー対象

ベースブランチは`git symbolic-ref refs/remotes/origin/HEAD`から解決し、得られなければリポジトリ情報で確認する。根拠なく`main`へ固定しない。

| 指定 | 差分コマンド |
|---|---|
| `staged` | `git diff --cached` |
| `working` | `git diff HEAD` |
| `pr` | `git diff {merge_base_sha}...HEAD` |
| `pr:{base}` | `git diff {merge_base_sha}...HEAD` |
| PR番号 / URL | `git diff {merge_base_sha}...HEAD` |

`pr` / `pr:{base}`では、検証済みbase refをshellへ埋め込まず、gitコマンドの引数として渡してmerge-baseを先に計算する。結果が完全なcommit SHAであることを検証して`{merge_base_sha}`へ入れる。

`--local`の`staged` / `working`は元diffをshared review directoryの`tmp/`にある0600 private patchへ1回保存し、同じbytesのSHA-256だけをrun fingerprintにする。本文を表示せず非空を確認し、4チャネルにはそのpatchだけを渡す。結果提示・編集・投稿の各直前にlive diffを再hashし、不一致なら編集・完了扱いせず新snapshotをレビューする。終了時はpatchを削除せず空へtruncateする。

PR指定時は`gh-ops`を読み、最初は`baseRefName`と`headRefOid`だけを取得する。baseと`refs/pull/{PR}/head`を別々の一意temporary refへfetchし、完全SHAとheadRefOid一致を検証してdetached専用worktreeへ展開する。remote-tracking ref、`FETCH_HEAD`、local branchを再利用せず、forkもbase repositoryのpull refを使う。本体checkoutをstash、reset、checkout、branch変更しない。作成後は `worktree` のローカル設定引き継ぎ、環境準備、具体的な作業コンテキストの引き渡しを行う。

PR本文、linked issue、commit、既存レビューはマージまで読まない。`{workdir}`は専用worktreeの絶対パスとする。

ローカル指定の`{workdir}`は、具体的な絶対パスで引き渡されたworktreeがあればそのパス、なければ`git rev-parse --show-toplevel`とする。変数名、相対パス、過去のシェル状態から補完しない。

### 隔離不変条件

セットアップ後、マージ前、修正前に検査する。失敗時は本体checkoutへフォールバックせず終了する。

- `git -C "{workdir}" rev-parse --show-toplevel`の結果が`{workdir}`と一致する
- `{workdir}`が`git worktree list --porcelain`に存在する
- PR指定または呼び出し元がworktree隔離必須とした場合、`{workdir}`は`dirname "$(git -C "{workdir}" rev-parse --path-format=absolute --git-common-dir)"`と異なる
- PR指定時は`git -C "{workdir}" rev-parse HEAD`が取得済み`headRefOid`と一致する
- `{workdir}`、成果物パス、CLIへ渡すその他のパスはcanonicalな絶対パスとし、shell sourceへ直接埋め込む場合は`[A-Za-z0-9._/ -]+`に収まらなければ停止する

## 出力

ローカル対象では `git -C "{workdir}" check-ignore tmp/` で除外を確認できれば、`{workdir}/tmp/` 内に `mktemp -d` で専用 `{artifact_dir}` を作る。除外されていなければ OS 一時領域に作り、パスを明示する。レビュー生成物を tracked 差分や commit へ混入させない。PR番号またはURL指定では、worktree削除後も結果を保持できるよう、`mktemp -d "${TMPDIR:-/tmp}/review-patch-crosscheck.XXXXXX"`でworktree外に専用`{artifact_dir}`を作る。

既存ファイルと衝突しない整数`{seq}`を実行ごとに採番する。並行実行による衝突を避けるため、canonical repository pathとprefixを`shasum`でhex keyへ変換し、`/tmp`配下の`{key}-{seq}.lock` directoryを`mkdir`で原子的に予約する。取得できなければ次のseqを試す。予約directoryは正常・異常終了を問わず削除せず、以後は次のseqを使う。

```text
{artifact_dir}/{prefix}-rules-agent_{seq}.md
{artifact_dir}/{prefix}-senior-codex_{seq}.md
{artifact_dir}/{prefix}-adversarial-codex_{seq}.md
{artifact_dir}/{prefix}-rules-codex_{seq}.md
{artifact_dir}/{prefix}-merged_{seq}.md
{artifact_dir}/{prefix}-timing_{seq}.log
{artifact_dir}/{prefix}-boundary-followup_{seq}.md
```

各チャネルの開始・終了epoch秒をtiming logへ`channel,attempt,start,end,result`形式で追記する。`result`はexit code、`timeout`、またはサブエージェントの完了状態とする。並列追記は1行単位で行う。rules-agent は phase1 / phase2 / phase2.5 / phase3 / write の開始 epoch 秒も計測し、最終応答の計測メタデータを呼び出し元が `rules-agent:{phase},attempt,epoch` 形式で追記する。フェーズ行は所要時間の分析専用とし、指摘の採否には使わない。

`codex exec review`は`cd "{workdir}"`で実行し、対象flagとPROMPT指定を併用しない。通常の`codex exec`は`-C "{workdir}"`を使う。

## 事前処理の禁止

4チャネル起動前に許される対象確認は、元のgit diffへ`--stat`を付けた空チェックだけとする。`--local`ではfingerprint計算と`staged` / `working`のprivate patch保存・非空検査も許すが、diff本文を表示・Read・分析しない。PR本文、linked issue、コミットメッセージ、既存レビューも読まず、内容分析、関連ルールの選別、レビュー観点の取捨選択を行わない。空ならチャネルを起動せず「レビュー対象なし」と終了する。

## 手順

### 1. セットアップ

1. 引数を厳密にパースし、前提を検証する。
2. PR指定時は専用worktreeを作成する。
3. `{workdir}`を確定し、隔離不変条件を検査する。
4. 固定した`base_sha`と`head_sha`からmerge-base SHAを計算し、差分コマンド、`{artifact_dir}`、絶対出力パス、`{seq}`を確定する。
5. 選択済み`review-patch` skill directoryをcanonicalな絶対パス`{review_patch_skill_dir}`として確定し、`SKILL.md`と必須referenceの存在を確認する。
6. 通常targetは元のgit diffを`--stat`だけで空確認する。private patch targetはpatchの非空検査とhash確定を行う。

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

Boundary Census節の欠落だけはチャネル失敗にせず、マージ時の境界カバレッジ監査で扱う。boundary-followupは通常チャネルの再試行規則の対象外とする。

禁止コマンドの実行結果はレビュー根拠に採用しない。

### 3. マージ

全チャネル完了後に[`references/merge-and-report.md`](references/merge-and-report.md)を全文読み、その「マージ」に従う。チャネル出力、PR本文、linked issue、コミットメッセージ、既存レビューはこの時点で初めて読む。

### 4. 結果提示と修正

同じreferenceの「結果提示と修正」に従う。`--local`のfinding生成・既存finding取得・投稿は、4チャネル完了後にmergedを検証してからだけ行う。

### 5. 完了報告

同じreferenceの「完了報告」に従う。
