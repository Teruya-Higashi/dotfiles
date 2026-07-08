---
name: review-changes-with-codex
description: サブエージェントと Codex の4系統で並列コードレビューを実施し、結果をマージして修正を行う。
---

# レビュースキル（with Codex）

サブエージェント（Agent ツール + `review-changes` スキル）、Codex シニアレビュー（`codex exec review` CLI）、
Codex adversarial レビュー（`codex exec` CLI）、Codex review-changes レビュー（`codex exec` CLI + `review-changes` スキル）の
4系統で同じ差分を並列でレビューさせ、全結果をマージした上で修正を適用するスキル。
マージした統合結果はファイルに書き出さず、`review-changes` スキルのレビューサマリー形式でユーザーに提示する。

Codex チャネルは plugin（`codex:codex-rescue` サブエージェント）や内部スクリプト（`codex-companion.mjs`）を経由せず、
`codex` バイナリを Bash から直接呼び出す。

- **サブエージェントレビュー**: Agent ツールを使用。`~/.agents/skills/review-changes/SKILL.md` をサブエージェント自身に読ませ、スキルの3フェーズレビュー手法（コンテキスト収集 → レビュー → Validation → フィルタリング）を実行させる
- **シニアレビュー**: `codex exec review` を使用。専用のレビューエンジンが自前の観点で差分を解析し、構造化された指摘（verdict / findings / next_steps）を返す（CLI 制約により観点指示は渡せない。後述）
- **adversarial レビュー**: プレーンな `codex exec` を使用。adversarial スタンスと出力フォーマットをプロンプトで完全制御する
- **review-changes レビュー**: プレーンな `codex exec` を使用。サブエージェントレビューと同様に `review-changes` スキルを Codex に実行させる（同一手法を呼び出し元 AI / Codex の2モデルで独立に走らせて突き合わせる）

モデルは `--model` / `--effort` オプションで指定でき、デフォルトは `gpt-5.5` + reasoning effort `xhigh`。サンドボックス・承認設定は `~/.codex/config.toml` に従う（`approval_policy = "never"` を前提）。

## 引数

```
/review-changes-with-codex [レビュー観点の追加指示]
```

- **レビュー観点の追加指示**: 省略時、Codex adversarial はデフォルトの10観点、サブエージェント / Codex review-changes は `review-changes` スキルの観点体系、Codex シニアはネイティブレビューエンジンのデフォルト観点でレビュー（任意。CLI 制約によりシニアチャネルには追加指示も渡らない）

## オプション

引数内に以下のキーワードが含まれる場合、対応するパラメータを切り替える。

| オプション | デフォルト | 引数内キーワード例 |
|---|---|---|
| レビュー対象 | `staged` | `--target working`, `--target pr`, `--target pr:develop` |
| 出力プレフィックス | `review` | `--prefix my-review` |
| Codex モデル | `gpt-5.5` | `--model gpt-5.4` |
| Codex effort | `xhigh` | `--effort high` |

**パース規則**:
- `--target {値}`, `--prefix {値}`, `--model {値}`, `--effort {値}` を引数から抽出し、残りをレビュー観点の追加指示として扱う
- キーワードが見つからなければデフォルト値を使用

**モデル**: `--model` / `--effort` は全 Codex チャネル（シニア / adversarial / review-changes）共通。CLI には `-m {model} -c model_reasoning_effort="{effort}"` を常に付与する（`--model` の値はそのまま `-m` に渡す。未指定時は `gpt-5.5` / `xhigh`）。

**レビューファイルへの書き出し**: 全 Codex チャネルとも `-o {ファイル}` でエージェントの最終メッセージをファイルに書き出す。

### レビュー対象（`--target`）

| target 値 | 説明 | 差分取得コマンド |
|---|---|---|
| `staged`（デフォルト） | ステージエリアの変更のみ | `git diff --cached` |
| `working` | ワーキングツリー全体（staged + unstaged） | `git diff HEAD` |
| `pr` | 現在のブランチ全体（vs デフォルトブランチ） | `git diff $(git merge-base HEAD main)...HEAD` |
| `pr:{base}` | 現在のブランチ全体（vs 指定ブランチ） | `git diff $(git merge-base HEAD {base})...HEAD` |

**ベースブランチ**: `main` は自動検出する（`git symbolic-ref refs/remotes/origin/HEAD` 等）。検出できない場合は `main` を仮定する。

**チャネルごとの target の扱い**: チャネルによって対象指定の手段が異なる。

| チャネル | target の渡し方 |
|---|---|
| サブエージェント | 上表の diff コマンドをプロンプトで渡し、サブエージェント自身が実行 |
| Codex adversarial（`codex exec`） | 上表の diff コマンドをプロンプトで渡し、Codex 自身が実行 |
| Codex review-changes（`codex exec`） | 上表の diff コマンドをプロンプトで渡し、Codex 自身が実行 |
| Codex シニア（`codex exec review`） | ネイティブレビューフラグに変換（下表） |

`codex exec review` は **staged-only レビュー非対応**。`--target` をネイティブフラグに変換する:

| target 値 | `codex exec review` のフラグ |
|---|---|
| `staged` | `--uncommitted`（staged のみは不可。staged+unstaged+untracked が対象になる） |
| `working` | `--uncommitted` |
| `pr` / `pr:{base}` | `--base {base}` |

**注意**: `--target staged` 指定時、シニアチャネルのみ unstaged の指摘が混入しうる。マージフェーズでシニアチャネルの指摘を staged ファイルに限定してフィルタリングする（他チャネルは staged の diff コマンドを渡すためフィルタ不要）。

出力ファイル名:
- `{prefix}-{ai_name}_{sequence_number}.md` — サブエージェント
- `{prefix}-codex_{sequence_number}.md` — Codex シニアレビュー
- `{prefix}-adversarial_{sequence_number}.md` — Codex adversarial レビュー
- `{prefix}-skill_{sequence_number}.md` — Codex review-changes レビュー

**`{ai_name}` の決定**: 現在スキルを実行している AI の名前を使用する（例: `claude`, `gemini` 等）。自身のモデル名から判定すること。

### 作業ディレクトリ

全チャネルは**レビュー対象リポジトリのルート**を作業ディレクトリとして動かす。worktree 上の変更をレビューする場合（例: PR 用に切った worktree）は worktree のパスが作業ディレクトリ（以下 `{workdir}`）になる。呼び出し元の cwd がすでに対象リポジトリなら追加の指定は不要。異なる場合、チャネルごとに指定方法が異なる:

| チャネル | 作業ディレクトリの指定方法 |
|---|---|
| サブエージェント | prompt に `{workdir}` を明記し、その中で diff・調査を実行させる |
| Codex adversarial / review-changes（`codex exec`） | `-C {workdir}` フラグ |
| Codex シニア（`codex exec review`） | `cd {workdir} && codex exec review ...` と前置（`-C` 非対応） |

**CLI 制約（重要）**: プレーンな `codex exec` は `-C, --cd <DIR>` を受理するが、`codex exec review` サブコマンドのパーサーは `-C` を認識しない。付けると `error: unexpected argument '-C' found`（exit code 2）で即座に失敗する。シニアチャネルはフラグに頼らず `cd {workdir} && ` の前置で作業ディレクトリを移すこと。

**出力ファイルのパス**: 作業ディレクトリを指定する場合、`-o` およびサブエージェントの出力ファイルは**絶対パス**で渡す（`cd` / `-C` により相対パスの解決先がチャネルごとにずれ、レビューファイルが散らばるため）。4チャネルのレビューファイルは同一ディレクトリに揃える。

## 重要: 事前処理の禁止

**このスキルの実行者（呼び出し元 AI）は、4チャネル起動前に以下を絶対に行わないこと:**

- `git diff --cached` や `git diff` の **内容**を読むこと（`--stat` による空チェックのみ許可）
- 変更されたファイルを Read ツールで読むこと
- コードの内容を分析・要約すること
- レビュー観点をユーザーの変更内容に合わせて取捨選択・カスタマイズすること
- 「この変更は〇〇なので△△の観点が重要」といった事前判断を行うこと

**理由**: 差分の取得・ファイルの読み取り・分析はすべて各チャネル（サブエージェント / Codex シニア / Codex adversarial / Codex review-changes）が自身で行う。呼び出し元が事前に情報を収集・加工すると、各チャネルの独立した視点が失われ、バイアスがかかる。

**やるべきこと**: 引数のパース → `--stat` で空チェック → 即座に4チャネル起動。それ以外の処理はすべてチャネルに委譲する。

## レビュー観点（10観点）

Codex adversarial チャネルにのみ prompt 本文に含めて渡すデフォルト観点。
Codex シニアレビュー（`codex exec review`）には渡さない（対象フラグと PROMPT 引数が CLI 上排他のため。観点選定はネイティブレビューエンジンに任せる）。
サブエージェントと Codex review-changes レビューにも渡さない（`review-changes` スキル自身の観点体系に従わせるため。ユーザーの追加指示のみ渡す）。
ユーザーの追加指示がある場合はこれにマージする。

1. 正確性・ロジック: バグ、エッジケース、nil安全性、競合状態
2. 設計・アーキテクチャ: 責務分離、抽象化レベル、SOLID原則
3. エラーハンドリング: エラーの伝播、ログレベルの適切性、リカバリー戦略
4. セキュリティ: ヘッダーインジェクション、入力バリデーション、情報漏洩
5. パフォーマンス: メモリ割り当て、ロック競合、N+1問題
6. 後方互換性: DBマイグレーション、API互換、既存データとの整合性
7. テスタビリティ: テストの追加・更新が必要な箇所
8. 命名・可読性: 変数名、コメントの正確性、コードの意図の明確さ
9. 言語慣習: 対象言語のイディオム準拠、error handling パターン
10. 不足している変更: この機能を完成させるために追加で必要な変更

## 手順

### 1. 引数パースと空チェック

引数からオプションを抽出した後、差分が存在するか **`--stat` のみで** 確認する:

| target | 空チェックコマンド |
|---|---|
| `staged` | `git diff --cached --stat` |
| `working` | `git diff HEAD --stat` |
| `pr` / `pr:{base}` | `git diff $(git merge-base HEAD {base})...HEAD --stat` |

差分が空の場合は「レビュー対象の変更がありません」と表示して終了する。
作業ディレクトリが呼び出し元の cwd と異なる場合（worktree 等）は `git -C {workdir} diff ... --stat` で実行する。

**禁止**: ここで `--stat` なしの `git diff` を実行して差分内容を読んではならない。

### 2. 並列レビューの実行（即座に起動）

空チェックを通過したら、**他の処理を一切挟まず**、4チャネルを**同時にバックグラウンドで**起動する。
必ず同一ターン内で全ての呼び出しを行うこと。

**禁止**: 起動前に差分内容の確認、ファイルの読み取り、変更概要の分析を行わないこと。

#### a. サブエージェントレビュー（Agent ツール + `review-changes` スキル）

サブエージェントにも `~/.agents/skills/review-changes/SKILL.md` を読ませ、スキルの3フェーズレビュー手法に従ってレビューさせる。
呼び出し元がスキル内容を要約・抜粋して prompt に埋め込まないこと（スキルの読み込みもサブエージェント自身が行う）。

`--target` に応じて、サブエージェントに実行させる diff コマンドを切り替える:

| target | サブエージェントに指示する diff コマンド |
|---|---|
| `staged` | `git diff --cached` |
| `working` | `git diff HEAD` |
| `pr` / `pr:{base}` | `git diff $(git merge-base HEAD {base})...HEAD` |

```
Agent(
  subagent_type: "general-purpose",
  mode: "bypassPermissions",
  run_in_background: true,
  prompt: "~/.agents/skills/review-changes/SKILL.md を読み、そのスキルの手順（3フェーズレビュー: コンテキスト収集 → レビュー → Validation → フィルタリング）に従って `{diff コマンド}` の差分をレビューし、結果を {prefix}-{ai_name}_{sequence_number}.md に書き出してください。

  スキル適用時の調整:
  - レビュー対象: スキルの引数解釈（PR 番号 / ブランチ等）に関わらず、`{diff コマンド}` の差分を対象とすること
  - 作業ディレクトリ: {workdir} 内で diff コマンドの実行・ファイル読み取り・調査を行うこと
  - 実行モード: 常にインラインモード（あなた自身が全観点を1パスでレビュー）とし、並列エージェントは起動しないこと
  - 出力: スキルの「レビューサマリー」フォーマット（テキストバッジ [critical] / [should] / [nits] / [ask]）に従うこと
  - スキル内の GitHub 投稿・レビュー後の修正・ユーザーへの確認は一切行わないこと
  {ユーザーの追加指示があればここに追記}

  差分の取得・関連ファイルの読み取り・影響範囲の調査はあなた自身で行うこと。
  ソースコードの変更は一切行わず、コンテキスト収集結果とレビューサマリーの全文をファイルに書き出すこと。"
)
```

#### b. Codex シニアレビュー（`codex exec review` CLI）

`codex exec review` を Bash ツールで `run_in_background: true` 起動する。
専用のレビューエンジンが差分の取得・解析・観点選定を行い、構造化された指摘を返す。

**CLI 制約（重要）**: `codex exec review` の対象フラグ（`--uncommitted` / `--base {branch}` / `--commit {sha}`）は PROMPT 引数（stdin の `-` 含む）と**排他**。
併用すると `error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`（exit code 2）で即座に失敗する。
このためシニアチャネルには 10観点もユーザー追加指示も**渡さない**。対象フラグのみで起動し、観点選定はネイティブレビューエンジンに任せる。
観点カバレッジは、10観点を受け取る adversarial チャネルと、`review-changes` スキルの観点体系を使うサブエージェント / Codex review-changes チャネルで担保する。

**CLI 制約（作業ディレクトリ）**: `codex exec review` は `-C` フラグも認識しない。付けると `error: unexpected argument '-C' found`（exit code 2）で即座に失敗する。作業ディレクトリの指定は `cd {workdir} && codex exec review ...` の前置で行う（「作業ディレクトリ」節参照）。

**設計上の注意**:
- 対象差分はネイティブフラグで指定する（プロンプトに diff コマンドを書かない）。`--target` を上述の変換表に従い `--uncommitted` / `--base {base}` に変換する
- PROMPT 引数・stdin（`- <<EOF`）は一切渡さない（上記 CLI 制約のため）
- 作業ディレクトリは `cd {workdir} && ` の前置で移す（`-C` は使えない）。このとき `-o` は絶対パスで渡す
- `-o {ファイル}` でレビュー結果（最終メッセージ）をレビューファイルに直接書き出す
- 出力フォーマットはネイティブレビューエンジンの形式（`verdict` / `summary` / `findings[severity, file, line, recommendation]` / `next_steps`）。カスタムマークダウン形式は強制しない
- `codex exec review` はレビュー専用でソースコードを変更しない

```bash
# --target staged / working の場合（cwd がレビュー対象リポジトリなら cd 前置は省略可）
cd {workdir} && codex exec review --uncommitted -m {model} -c model_reasoning_effort="{effort}" \
  -o {prefix}-codex_{sequence_number}.md

# --target pr / pr:{base} の場合
cd {workdir} && codex exec review --base {base} -m {model} -c model_reasoning_effort="{effort}" \
  -o {prefix}-codex_{sequence_number}.md
```

**フラグの構築**:
- `cd {workdir} && ` → 作業ディレクトリの指定（`codex exec review` は `-C` 非対応のため前置で移す。cwd が対象リポジトリなら省略可）
- 対象フラグ → `--target` から変換（`staged`/`working` → `--uncommitted`、`pr`/`pr:{base}` → `--base {base}`）。PROMPT 引数とは排他のため、対象フラグを使う本スキルでは PROMPT を渡さない
- `-m {model} -c model_reasoning_effort="{effort}"` → 常に付与（未指定時は `gpt-5.5` / `xhigh`）
- `-o {prefix}-codex_{sequence_number}.md` → 常に付与（レビューファイル書き出しのため。`cd` を前置する場合は絶対パスで渡す）
- サンドボックス・承認は `~/.codex/config.toml` に従う（`workspace-write` / `never` 前提）

#### c. Codex adversarial レビュー（`codex exec` CLI）

プレーンな `codex exec` を Bash ツールで `run_in_background: true` 起動する。
ネイティブレビューエンジンは使わず、adversarial スタンスと出力フォーマットをプロンプトで完全制御する。
「この変更が ship すべきでない理由」を積極的に探し、実装方針・設計選択・前提条件に疑義を唱えるフレーミングで書く。

`--target` に応じて Codex に実行させる diff コマンドを切り替える（上述の diff コマンド表に従う）。
プロンプトは多行のため heredoc で stdin から渡す。

```bash
codex exec -C {workdir} -m {model} -c model_reasoning_effort="{effort}" \
  -o {prefix}-adversarial_{sequence_number}.md - <<'EOF'
Adversarial reviewer として `{diff コマンド}` の差分をレビューしてください。

スタンス:
- この変更を ship すべきでない理由を積極的に探すこと
- 単なる実装のバグ洗いではなく、採用されたアプローチ自体が正しいか、どの前提に依存しているか、実環境で設計が崩れうる箇所はどこかを問うこと
- 設計選択・トレードオフ・暗黙の仮定を疑うこと
- 観点が弱い指摘より、approach-level な疑義や設計レベルの欠陥を優先すること

重要:
- 差分の取得・関連ファイルの読み取り・既存パターンの調査はあなた自身で行うこと
- ソースコードの変更は一切行わず、レビュー結果のみを出力すること
- 以下10観点を念頭に置きつつ、通常レビューと差別化される「攻撃的な」指摘を優先すること: {10観点をそのまま列挙} {ユーザーの追加指示があればここに追記}

出力フォーマット:

# Adversarial Review: {変更の要約}

## アプローチへの疑義
[採用されたアプローチそのものへの批判]

## 前提の脆さ
[暗黙の仮定・依存先の脆さ]

## 設計レベルの欠陥
[実環境で崩れうる設計箇所]

## Critical / Warning / Info
[従来の指摘カテゴリ。該当箇所はファイル:行番号を明記]

## 見送り判断の材料
[ship すべきでないと判断する根拠]

重要: あなたの最終応答（last message）として、上記フォーマットのレビュー全文を出力すること。
全セクション・全指摘を省略せず、要約ではなく全文を最終メッセージに含めること。
EOF
```

**フラグの構築**:
- `-C {workdir}` → 作業ディレクトリの指定（プレーンな `codex exec` は `-C` を受理する。cwd が対象リポジトリなら省略可）
- `-m {model} -c model_reasoning_effort="{effort}"` → 常に付与（未指定時は `gpt-5.5` / `xhigh`）
- `-o {prefix}-adversarial_{sequence_number}.md` → 常に付与（レビューファイル書き出しのため。`-C` を付ける場合は絶対パスで渡す）
- サンドボックス・承認は `~/.codex/config.toml` に従う（`workspace-write` / `never` 前提）

#### d. Codex review-changes レビュー（`codex exec` CLI + `review-changes` スキル）

プレーンな `codex exec` を Bash ツールで `run_in_background: true` 起動する。
`~/.agents/skills/review-changes/SKILL.md` を Codex 自身に読ませ、スキルの3フェーズレビュー手法
（コンテキスト収集 → レビュー → Validation → フィルタリング）に従ってレビューさせる。
呼び出し元がスキル内容を要約・抜粋して prompt に埋め込まないこと（スキルの読み込みも Codex 自身が行う）。

`--target` に応じて Codex に実行させる diff コマンドを切り替える（上述の diff コマンド表に従う）。
プロンプトは多行のため heredoc で stdin から渡す。

```bash
codex exec -C {workdir} -m {model} -c model_reasoning_effort="{effort}" \
  -o {prefix}-skill_{sequence_number}.md - <<'EOF'
~/.agents/skills/review-changes/SKILL.md を読み、そのスキルの手順（3フェーズレビュー: コンテキスト収集 → レビュー → Validation → フィルタリング）に従って `{diff コマンド}` の差分をレビューしてください。

スキル適用時の調整:
- レビュー対象: スキルの引数解釈（PR 番号 / ブランチ等）に関わらず、`{diff コマンド}` の差分を対象とすること
- 実行モード: 常にインラインモード（あなた自身が全観点を1パスでレビュー）とし、並列エージェントは起動しないこと
- 出力: スキルの「レビューサマリー」フォーマット（テキストバッジ [critical] / [should] / [nits] / [ask]）に従うこと
- スキル内の GitHub 投稿・レビュー後の修正・ユーザーへの確認は一切行わないこと
{ユーザーの追加指示があればここに追記}

重要:
- 差分の取得・関連ファイルの読み取り・影響範囲の調査はあなた自身で行うこと
- ソースコードの変更は一切行わず、レビュー結果のみを出力すること
- あなたの最終応答（last message）として、コンテキスト収集結果とレビューサマリーの全文を出力すること。
  全指摘を省略せず、要約ではなく全文を最終メッセージに含めること
EOF
```

**フラグの構築**:
- `-C {workdir}` → 作業ディレクトリの指定（プレーンな `codex exec` は `-C` を受理する。cwd が対象リポジトリなら省略可）
- `-m {model} -c model_reasoning_effort="{effort}"` → 常に付与（未指定時は `gpt-5.5` / `xhigh`）
- `-o {prefix}-skill_{sequence_number}.md` → 常に付与（レビューファイル書き出しのため。`-C` を付ける場合は絶対パスで渡す）
- サンドボックス・承認は `~/.codex/config.toml` に従う（`workspace-write` / `never` 前提）

### 3. 完了待ち

全てのバックグラウンドタスクの完了通知を受け取る。
ユーザーから途中経過の確認があった場合は `TaskOutput`（`block: false`）で状態を報告する。

進捗テーブルを表示して状況を共有する:

```markdown
| タスク | 状態 |
|---|---|
| {ai_name} レビュー → `{prefix}-{ai_name}_{seq}.md` | 完了 / 実行中 |
| Codex シニアレビュー → `{prefix}-codex_{seq}.md` | 完了 / 実行中 |
| Codex adversarial → `{prefix}-adversarial_{seq}.md` | 完了 / 実行中 |
| Codex review-changes → `{prefix}-skill_{seq}.md` | 完了 / 実行中 |
| マージ・修正 | 待機 |
```

### 4. レビュー結果のマージ・分析

4つのレビューファイルを Read ツールで読み込む。出力形式はチャネルにより異なる:
- サブエージェント / Codex review-changes: `review-changes` スキルのレビューサマリー形式（タグ: `critical` / `should` / `nits` / `ask`）
- Codex シニア: `codex exec review` のネイティブ形式（`verdict` / `summary` / `findings` / `next_steps`）
- Codex adversarial: 指定したカスタムマークダウン形式

**タグの統一**: 統合結果は `review-changes` スキルのタグ体系（`critical` / `should` / `nits` / `ask`）に揃える。他チャネルの severity は以下の対応で読み替える:

| チャネル側の severity | 統一タグ |
|---|---|
| Critical（adversarial）/ シニアの重大な findings | `critical` |
| Warning（adversarial）/ シニアの中程度の findings | `should` |
| Info（adversarial）/ シニアの軽微な findings | `nits` |
| 意図確認が必要な指摘 | `ask` |

`--target staged` の場合、シニアチャネル（`--uncommitted`）の指摘には unstaged の変更が混入しうる。
`git diff --cached --name-only` で staged ファイル一覧を取得し、シニアチャネルの指摘を staged ファイルに限定してフィルタリングしてからマージする。

以下の方針で 4-way マージする:

#### マージ優先度

| 指摘元 | 信頼度 | 扱い |
|---|---|---|
| 3者以上共通 | 最高 | 最優先で対応 |
| 2者共通 | 高 | 対応推奨 |
| サブエージェントのみ | 中〜高 | スキルの Validation で裏取り済みの指摘、evidence（発火条件）を確認して判断 |
| Codex シニアのみ | 中 | 第三者視点の発見として評価 |
| adversarial のみ | 中〜高 | 攻撃的スタンスならではの発見、根拠を確認して判断 |
| review-changes のみ | 中〜高 | スキルの Validation で裏取り済みの指摘、evidence（発火条件）を確認して判断 |

#### マージ手順

1. **3者以上共通の指摘**: 最高優先度として統合
2. **2者共通の指摘**: 高優先度として統合、どの2者かを記録
3. **単独の指摘**: 内容を精査し、根拠が十分であれば採用
4. **矛盾する指摘**: 各チャネルの根拠を比較し、コード文脈を確認した上でより妥当な方を採用
5. **重複の統合**: 同一箇所への重複指摘を1つにまとめる

### 5. マージ結果の提示とユーザー確認

統合結果は md ファイルに書き出さず、`review-changes` スキルの出力フォーマット（レビューサマリー + 指摘の書き方、テキストバッジ）で会話内に直接提示する。
チャネルごとの md ファイルは中間成果物としてそのまま残す。

サマリーは `review-changes` スキルの「レビューサマリー」構造に「指摘元」列を追加したもの:

```markdown
## レビューサマリー

**変更の意図**: {サブエージェント / Codex review-changes チャネルのコンテキスト収集結果を統合}
**影響範囲**: {同上}

### 指摘一覧

| # | ファイル:行 | タグ | 概要 | 指摘元 | 対応 |
|---|-----------|------|------|--------|------|
| 1 | path/to/file.go:42 | critical | 説明 | 4者共通 | **対応推奨** — 理由 |
| 2 | path/to/file.go:80 | should | 説明 | {ai_name}+adversarial | **対応推奨** — 理由 |
| 3 | path/to/file.go:55 | should | 説明 | Codex シニア | **対応不要** — 理由 |
| 4 | path/to/file.go:100 | ask | 説明 | review-changes | **要確認** — 理由 |

### 判定: {APPROVE / REQUEST_CHANGES / COMMENT}
```

各指摘の詳細は `review-changes` スキルの「指摘の書き方」に従い、テキストバッジ（`[critical]` / `[should]` / `[nits]` / `[ask]`）・ファイルパスと行番号・問題の説明・根拠・修正案・対応判定を含めて提示する。

AskUserQuestion でユーザーに確認を取る:
- どの指摘に対応するか（multiSelect）
- 対応方針の変更があるか

**重要**: ユーザーの確認なしにコード修正を行わない。

#### GitHub への投稿（サマリコメント）

GitHub へレビューを投稿する場合は、`review-changes` スキルの「GitHub 投稿」節に従う（投稿前のユーザー確認・デフォルト event は COMMENT・投稿フォーマット・画像バッジ）。

投稿する本文（サマリーコメント・インラインコメント）は、`review-changes` スキルのサマリー構造と「指摘の書き方」のみで構成する。すなわち変更の意図・影響範囲・指摘一覧・判定・各指摘の詳細だけを書く。

- 「指摘元」列は会話内提示専用。投稿するサマリーの指摘一覧からは除き、`review-changes` スキルのサマリー構造（指摘元列なし）で投稿する
- レビューの実施体制 — 誰が・何系統で・どのようにレビューしたか（例:「4系統の並列レビュー（Claude サブエージェント / Codex シニア / Codex adversarial / Codex review-changes）の統合結果から」）— は本文に書かない。読み手に必要なのは指摘内容であり、レビュー手法ではない

### 6. 修正の適用

ユーザーが承認した指摘について修正を実施する:

1. 対象ファイルを Read → Edit で修正
2. 対象ファイルの言語に応じた lint/test を実行
3. テストが失敗した場合は原因を分析し、修正を再試行

### 7. 結果の報告

修正完了後、以下をユーザーに報告する:
- 対応した指摘の一覧
- スキップした指摘とその理由
- lint/test の実行結果

## 注意事項

### 事前処理の禁止（最重要）

- **4チャネル起動前に差分内容を読まない**。`--stat` による空チェックのみ許可。`--stat` なしの `git diff` は禁止
- **4チャネル起動前に変更ファイルを Read しない**。ファイルの中身を確認するのはチャネルの仕事
- **4チャネル起動前にコードを分析・要約しない**。「この変更は〇〇の修正で…」のような事前まとめは不要
- **レビュー観点の取捨選択をしない**。10観点はそのままチャネルに渡す。呼び出し元が「この変更にはセキュリティ観点は不要」等の判断をしない
- **サブエージェントの prompt に差分内容を埋め込まない**。各チャネル自身に diff コマンドを実行させる

### 実行ルール

- 4チャネルは必ず**並列で**起動すること（同一ターン内で Agent ツール1本と Bash ツール3本を起動する）
- Codex チャネルは `codex` バイナリを Bash から直接呼び出す。plugin（`codex:codex-rescue`）や `codex-companion.mjs` は経由しない
- シニアチャネルは `codex exec review`（ネイティブレビューエンジン）、adversarial / review-changes チャネルはプレーンな `codex exec` を使う
- サブエージェント / Codex review-changes チャネルは `~/.agents/skills/review-changes/SKILL.md` を各チャネル自身に読ませて手順に従わせる。呼び出し元がスキル内容を要約して prompt に埋め込まない
- サブエージェント / Codex review-changes チャネルでは、スキル内の GitHub 投稿・レビュー後の修正・ユーザー確認フェーズを実行させない（レビュー結果の出力のみ）
- `codex exec review` は staged-only レビュー非対応。`--target` は `--uncommitted` / `--base {base}` に変換する
- `codex exec review` の対象フラグ（`--uncommitted` / `--base` / `--commit`）は PROMPT 引数と排他。シニアチャネルには PROMPT・stdin を渡さず、観点はネイティブレビューエンジンに任せる
- 全チャネルの作業ディレクトリはレビュー対象リポジトリ（worktree 含む）に揃える。プレーンな `codex exec` は `-C {workdir}` で指定できるが、`codex exec review` は `-C` 非対応（`error: unexpected argument '-C' found`、exit code 2）のため `cd {workdir} && ` を前置する
- 作業ディレクトリを指定する場合、レビューファイル（`-o` / サブエージェント出力）は絶対パスで同一ディレクトリに揃える
- `codex exec` / `codex exec review` はレビュー専用でソースコードを変更しない。プロンプトでもコード変更を禁止し、レビュー結果のみを出力させる
- レビューファイルは `-o {ファイル}` でエージェントの最終メッセージを書き出す
- モデルは `--model` / `--effort` で指定（デフォルト `gpt-5.5` / `xhigh`）、全 Codex チャネル共通

### マージ・修正ルール

- レビュー結果のマージはユーザーに提示してから修正に入る
- 統合結果は md ファイルに書き出さず、`review-changes` スキルのレビューサマリー形式（タグ体系 `critical` / `should` / `nits` / `ask`、テキストバッジ）で会話内に提示する
- GitHub への投稿は `review-changes` スキルの「GitHub 投稿」節に従う。投稿本文は `review-changes` スキルのサマリー構造と「指摘の書き方」のみで構成し、「指摘元」列やレビュー体制の説明（チャネル構成・「N系統の統合結果」等）は含めない
- 各チャネルの指摘が矛盾する場合は、コードの文脈を確認した上で判断理由を明記する
- `--target staged` 指定時、シニアチャネルは `codex exec review --uncommitted` のため unstaged の指摘が混入しうる。マージ前に `git diff --cached --name-only` で staged ファイルに限定してフィルタリングする（サブエージェント・adversarial・review-changes チャネルは `git diff --cached` を渡すためフィルタ不要）
