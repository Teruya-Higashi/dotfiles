---
name: review-with-codex
description: サブエージェントと Codex の3系統で並列コードレビューを実施し、結果をマージして修正を行う。
---

# レビュースキル（with Codex）

サブエージェント（Agent ツール）、Codex シニアレビュー（`codex exec review` CLI）、Codex adversarial レビュー（`codex exec` CLI）の
3系統で同じ差分を並列でレビューさせ、全結果をマージした上で修正を適用するスキル。

Codex チャネルは plugin（`codex:codex-rescue` サブエージェント）や内部スクリプト（`codex-companion.mjs`）を経由せず、
`codex` バイナリを Bash から直接呼び出す。

- **シニアレビュー**: `codex exec review` を使用。専用のレビューエンジンが構造化された指摘（verdict / findings / next_steps）を返す
- **adversarial レビュー**: プレーンな `codex exec` を使用。adversarial スタンスと出力フォーマットをプロンプトで完全制御する

モデルは `--model` / `--effort` オプションで指定でき、デフォルトは `gpt-5.5` + reasoning effort `xhigh`。サンドボックス・承認設定は `~/.codex/config.toml` に従う（`approval_policy = "never"` を前提）。

## 引数

```
/review-with-codex [レビュー観点の追加指示]
```

- **レビュー観点の追加指示**: 省略時はデフォルトの10観点でレビュー（任意）

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

**モデル**: `--model` / `--effort` は両 Codex チャネル共通。CLI には `-m {model} -c model_reasoning_effort="{effort}"` を常に付与する（`--model` の値はそのまま `-m` に渡す。未指定時は `gpt-5.5` / `xhigh`）。

**レビューファイルへの書き出し**: 両 Codex チャネルとも `-o {ファイル}` でエージェントの最終メッセージをファイルに書き出す。

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

**`{ai_name}` の決定**: 現在スキルを実行している AI の名前を使用する（例: `claude`, `gemini` 等）。自身のモデル名から判定すること。

## 重要: 事前処理の禁止

**このスキルの実行者（呼び出し元 AI）は、3チャネル起動前に以下を絶対に行わないこと:**

- `git diff --cached` や `git diff` の **内容**を読むこと（`--stat` による空チェックのみ許可）
- 変更されたファイルを Read ツールで読むこと
- コードの内容を分析・要約すること
- レビュー観点をユーザーの変更内容に合わせて取捨選択・カスタマイズすること
- 「この変更は〇〇なので△△の観点が重要」といった事前判断を行うこと

**理由**: 差分の取得・ファイルの読み取り・分析はすべて各チャネル（サブエージェント / Codex シニア / Codex adversarial）が自身で行う。呼び出し元が事前に情報を収集・加工すると、各チャネルの独立した視点が失われ、バイアスがかかる。

**やるべきこと**: 引数のパース → `--stat` で空チェック → 即座に3チャネル起動。それ以外の処理はすべてチャネルに委譲する。

## レビュー観点（10観点）

全チャネルに渡すデフォルト観点。サブエージェントと Codex adversarial レビューは prompt 本文に含め、
Codex シニアレビュー（`codex exec review`）は重点観点として PROMPT 引数で渡す。
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

**禁止**: ここで `--stat` なしの `git diff` を実行して差分内容を読んではならない。

### 2. 並列レビューの実行（即座に起動）

空チェックを通過したら、**他の処理を一切挟まず**、3チャネルを**同時にバックグラウンドで**起動する。
必ず同一ターン内で全ての呼び出しを行うこと。

**禁止**: 起動前に差分内容の確認、ファイルの読み取り、変更概要の分析を行わないこと。

#### a. サブエージェントレビュー（Agent ツール）

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
  prompt: "シニアエンジニアとして {diff コマンド} の差分をレビューし、{prefix}-{ai_name}_{sequence_number}.md に書き出してください。..."
)
```

レビュー結果の出力形式:

```markdown
# Code Review: {変更の要約} ({ai_name})

## 総評
[全体的な評価とサマリー]

## Critical（修正必須）
[重大な問題。対象ファイル:行番号を明記]

## Warning（修正推奨）
[注意が必要な問題。対象ファイル:行番号を明記]

## Info（改善提案）
[ベストプラクティスに基づく提案]

## テスト要件
[追加・更新が必要なテスト]

## 不足している変更
[機能完成のために必要な追加変更]
```

#### b. Codex シニアレビュー（`codex exec review` CLI）

`codex exec review` を Bash ツールで `run_in_background: true` 起動する。
専用のレビューエンジンが差分の取得・解析を行い、構造化された指摘を返す。

**設計上の注意**:
- 対象差分はネイティブフラグで指定する（プロンプトに diff コマンドを書かない）。`--target` を上述の変換表に従い `--uncommitted` / `--base {base}` に変換する
- `-o {ファイル}` でレビュー結果（最終メッセージ）をレビューファイルに直接書き出す
- 出力フォーマットはネイティブレビューエンジンの形式（`verdict` / `summary` / `findings[severity, file, line, recommendation]` / `next_steps`）。カスタムマークダウン形式は強制しない
- PROMPT 引数に 10観点 + ユーザー追加指示を「重点的に確認してほしい観点」として渡す
- `codex exec review` はレビュー専用でソースコードを変更しない

```bash
# --target staged / working の場合
codex exec review --uncommitted -m {model} -c model_reasoning_effort="{effort}" \
  -o {prefix}-codex_{sequence_number}.md - <<'EOF'
以下の観点を重点的に確認してください:
{10観点をそのまま列挙} {ユーザーの追加指示があればここに追記}
EOF

# --target pr / pr:{base} の場合
codex exec review --base {base} -m {model} -c model_reasoning_effort="{effort}" \
  -o {prefix}-codex_{sequence_number}.md - <<'EOF'
以下の観点を重点的に確認してください:
{10観点をそのまま列挙} {ユーザーの追加指示があればここに追記}
EOF
```

**フラグの構築**:
- 対象フラグ → `--target` から変換（`staged`/`working` → `--uncommitted`、`pr`/`pr:{base}` → `--base {base}`）
- `-m {model} -c model_reasoning_effort="{effort}"` → 常に付与（未指定時は `gpt-5.5` / `xhigh`）
- `-o {prefix}-codex_{sequence_number}.md` → 常に付与（レビューファイル書き出しのため）
- サンドボックス・承認は `~/.codex/config.toml` に従う（`workspace-write` / `never` 前提）

#### c. Codex adversarial レビュー（`codex exec` CLI）

プレーンな `codex exec` を Bash ツールで `run_in_background: true` 起動する。
ネイティブレビューエンジンは使わず、adversarial スタンスと出力フォーマットをプロンプトで完全制御する。
「この変更が ship すべきでない理由」を積極的に探し、実装方針・設計選択・前提条件に疑義を唱えるフレーミングで書く。

`--target` に応じて Codex に実行させる diff コマンドを切り替える（上述の diff コマンド表に従う）。
プロンプトは多行のため heredoc で stdin から渡す。

```bash
codex exec -m {model} -c model_reasoning_effort="{effort}" \
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
- `-m {model} -c model_reasoning_effort="{effort}"` → 常に付与（未指定時は `gpt-5.5` / `xhigh`）
- `-o {prefix}-adversarial_{sequence_number}.md` → 常に付与（レビューファイル書き出しのため）
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
| マージ・修正 | 待機 |
```

### 4. レビュー結果のマージ・分析

3つのレビューファイルを Read ツールで読み込む。出力形式はチャネルにより異なる:
- サブエージェント / adversarial: 指定したカスタムマークダウン形式
- Codex シニア: `codex exec review` のネイティブ形式（`verdict` / `summary` / `findings` / `next_steps`）

`--target staged` の場合、シニアチャネル（`--uncommitted`）の指摘には unstaged の変更が混入しうる。
`git diff --cached --name-only` で staged ファイル一覧を取得し、シニアチャネルの指摘を staged ファイルに限定してフィルタリングしてからマージする。

以下の方針で 3-way マージする:

#### マージ優先度

| 指摘元 | 信頼度 | 扱い |
|---|---|---|
| 3者共通 | 最高 | 最優先で対応 |
| 2者共通 | 高 | 対応推奨 |
| サブエージェントのみ | 中 | 標準的な指摘として妥当性を評価 |
| Codex シニアのみ | 中 | 第三者視点の発見として評価 |
| adversarial のみ | 中〜高 | 攻撃的スタンスならではの発見、根拠を確認して判断 |

#### マージ手順

1. **3者共通の指摘**: 最高優先度として統合
2. **2者共通の指摘**: 高優先度として統合、どの2者かを記録
3. **単独の指摘**: 内容を精査し、根拠が十分であれば採用
4. **矛盾する指摘**: 3者の根拠を比較し、コード文脈を確認した上でより妥当な方を採用
5. **重複の統合**: 同一箇所への重複指摘を1つにまとめる

### 5. マージ結果の提示とユーザー確認

統合したレビュー結果をユーザーに提示する:

```markdown
| # | ファイル | 重要度 | 内容 | 指摘元 | 対応方針 |
|---|---------|--------|------|--------|----------|
| 1 | path/to/file.go:42 | Critical | 説明 | 3者共通 | 修正する |
| 2 | path/to/file.go:80 | Warning | 説明 | {ai_name}+adversarial | 修正する |
| 3 | path/to/file.go:55 | Warning | 説明 | Codex シニア | 修正する |
| 4 | path/to/file.go:100 | Info | 説明 | adversarial | スキップ — 理由 |
```

AskUserQuestion でユーザーに確認を取る:
- どの指摘に対応するか（multiSelect）
- 対応方針の変更があるか

**重要**: ユーザーの確認なしにコード修正を行わない。

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

- **3チャネル起動前に差分内容を読まない**。`--stat` による空チェックのみ許可。`--stat` なしの `git diff` は禁止
- **3チャネル起動前に変更ファイルを Read しない**。ファイルの中身を確認するのはチャネルの仕事
- **3チャネル起動前にコードを分析・要約しない**。「この変更は〇〇の修正で…」のような事前まとめは不要
- **レビュー観点の取捨選択をしない**。10観点はそのままチャネルに渡す。呼び出し元が「この変更にはセキュリティ観点は不要」等の判断をしない
- **サブエージェントの prompt に差分内容を埋め込まない**。各チャネル自身に diff コマンドを実行させる

### 実行ルール

- 3チャネルは必ず**並列で**起動すること（同一ターン内で Agent ツールと Bash ツール2本を起動する）
- Codex チャネルは `codex` バイナリを Bash から直接呼び出す。plugin（`codex:codex-rescue`）や `codex-companion.mjs` は経由しない
- シニアチャネルは `codex exec review`（ネイティブレビューエンジン）、adversarial チャネルはプレーンな `codex exec` を使う
- `codex exec review` は staged-only レビュー非対応。`--target` は `--uncommitted` / `--base {base}` に変換する
- `codex exec` / `codex exec review` はレビュー専用でソースコードを変更しない。プロンプトでもコード変更を禁止し、レビュー結果のみを出力させる
- レビューファイルは `-o {ファイル}` でエージェントの最終メッセージを書き出す
- モデルは `--model` / `--effort` で指定（デフォルト `gpt-5.5` / `xhigh`）、両 Codex チャネル共通

### マージ・修正ルール

- レビュー結果のマージはユーザーに提示してから修正に入る
- 3者の指摘が矛盾する場合は、コードの文脈を確認した上で判断理由を明記する
- `--target staged` 指定時、シニアチャネルは `codex exec review --uncommitted` のため unstaged の指摘が混入しうる。マージ前に `git diff --cached --name-only` で staged ファイルに限定してフィルタリングする（サブエージェント・adversarial チャネルは `git diff --cached` を渡すためフィルタ不要）
