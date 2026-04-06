---
name: review-with-codex
description: サブエージェントと Codex の3系統で並列コードレビューを実施し、結果をマージして修正を行う。
---

# レビュースキル（with Codex）

サブエージェント（Agent ツール）、Codex 組み込みレビュー（`codex:review`）、Codex adversarial レビュー（`codex:adversarial-review`）の
3系統で同じ差分を並列でレビューさせ、全結果をマージした上で修正を適用するスキル。

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
| Codex モデル | `gpt-5.4` | `--model spark` |

**パース規則**:
- `--target {値}`, `--prefix {値}`, `--model {値}` を引数から抽出し、残りをレビュー観点の追加指示として扱う
- キーワードが見つからなければデフォルト値を使用
- **注意**: `codex:review` / `codex:adversarial-review` は `--effort` を受け付けない（`--model` のみ対応）

### レビュー対象（`--target`）

| target 値 | 説明 | サブエージェント | Codex review / adversarial-review |
|---|---|---|---|
| `staged`（デフォルト） | ステージエリアの変更のみ | `git diff --cached` | `--scope working-tree` ※1 |
| `working` | ワーキングツリー全体（staged + unstaged） | `git diff HEAD` | `--scope working-tree` |
| `pr` | 現在のブランチ全体（vs デフォルトブランチ） | `git diff $(git merge-base HEAD main)...HEAD` ※2 | `--scope branch` |
| `pr:{base}` | 現在のブランチ全体（vs 指定ブランチ） | `git diff $(git merge-base HEAD {base})...HEAD` | `--base {base}` |

**※1 Codex の制約**: `codex-companion.mjs` は staged-only レビューをサポートしていない。`--target staged` の場合、Codex チャネルは `--scope working-tree`（staged + unstaged）でレビューする。マージフェーズで Codex の指摘を staged ファイルのみにフィルタリングする。

**※2 ベースブランチ**: `main` は自動検出する（`git symbolic-ref refs/remotes/origin/HEAD` 等）。検出できない場合は `main` を仮定する。

出力ファイル名:
- `{prefix}-{ai_name}_{sequence_number}.md` — サブエージェント
- `{prefix}-codex_{sequence_number}.md` — Codex 組み込みレビュー
- `{prefix}-adversarial_{sequence_number}.md` — Codex adversarial レビュー

**`{ai_name}` の決定**: 現在スキルを実行している AI の名前を使用する（例: `claude`, `gemini` 等）。自身のモデル名から判定すること。

## 重要: 事前処理の禁止

**このスキルの実行者（呼び出し元 AI）は、3チャネル起動前に以下を絶対に行わないこと:**

- `git diff --cached` や `git diff` の **内容**を読むこと（`--stat` による空チェックのみ許可）
- 変更されたファイルを Read ツールで読むこと
- コードの内容を分析・要約すること
- レビュー観点をユーザーの変更内容に合わせて取捨選択・カスタマイズすること
- 「この変更は〇〇なので△△の観点が重要」といった事前判断を行うこと

**理由**: 差分の取得・ファイルの読み取り・分析はすべて各チャネル（サブエージェント / Codex review / Codex adversarial-review）が自身で行う。呼び出し元が事前に情報を収集・加工すると、各チャネルの独立した視点が失われ、バイアスがかかる。

**やるべきこと**: 引数のパース → `--stat` で空チェック → 即座に3チャネル起動。それ以外の処理はすべてチャネルに委譲する。

## レビュー観点（10観点）

サブエージェントと adversarial-review の prompt に含めるデフォルト観点。
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

#### b. Codex 組み込みレビュー（`codex-companion.mjs review`）

codex plugin の組み込みレビューAPI を使用する。
Codex 内部の最適化されたレビューロジックで差分を分析する。

**注意**: `codex:review` コマンドは `disable-model-invocation: true` のため Skill ツールから呼び出せない。
`codex-companion.mjs` を Bash で直接実行する。

`--target` に応じて Codex のスコープフラグを切り替える:

| target | Codex フラグ |
|---|---|
| `staged` | `--scope working-tree` ※ |
| `working` | `--scope working-tree` |
| `pr` | `--scope branch` |
| `pr:{base}` | `--base {base}` |

※ Codex は staged-only レビューをサポートしていないため、working-tree で代替する。マージフェーズで staged ファイルのみにフィルタリングする。

```
Bash(
  command: 'CODEX_COMPANION="$(find ~/.claude/plugins -path "*/codex/scripts/codex-companion.mjs" -type f 2>/dev/null | head -1)" && node "$CODEX_COMPANION" review --wait --model {モデル} {scope_flag}',
  run_in_background: true,
  timeout: 600000
)
```

出力は Markdown テキストで stdout に返される。
完了後、結果を `{prefix}-codex_{sequence_number}.md` に Write ツールで書き出す。

**注意**: `codex:review` は focus text を受け付けないため、カスタム観点の指定はできない。
Codex 組み込みのレビューロジックにそのまま任せる。

#### c. Codex adversarial レビュー（`codex-companion.mjs adversarial-review`）

codex plugin の adversarial レビューを使用する。
「この変更が ship すべきでない理由」を積極的に探す攻撃的スタンスでレビューする。
focus text で10観点を渡してレビュー範囲を指示する。

**注意**: `codex:adversarial-review` コマンドも同様に Skill ツールから呼び出せない。

スコープフラグは b. と同じマッピングを使う。

```
Bash(
  command: 'CODEX_COMPANION="$(find ~/.claude/plugins -path "*/codex/scripts/codex-companion.mjs" -type f 2>/dev/null | head -1)" && node "$CODEX_COMPANION" adversarial-review --wait --model {モデル} {scope_flag} "以下の観点で重点的にレビューすること: {10観点のサマリー + ユーザー追加指示}"',
  run_in_background: true,
  timeout: 600000
)
```

出力は Markdown テキスト（plugin 内部で JSON → Markdown に変換済み）で stdout に返される。
完了後、結果を `{prefix}-adversarial_{sequence_number}.md` に Write ツールで書き出す。

### 4. 完了待ち

全てのバックグラウンドタスクの完了通知を受け取る。
ユーザーから途中経過の確認があった場合は `TaskOutput`（`block: false`）で状態を報告する。

進捗テーブルを表示して状況を共有する:

```markdown
| タスク | 状態 |
|---|---|
| {ai_name} レビュー → `{prefix}-{ai_name}_{seq}.md` | 完了 / 実行中 |
| Codex レビュー → `{prefix}-codex_{seq}.md` | 完了 / 実行中 |
| Codex adversarial → `{prefix}-adversarial_{seq}.md` | 完了 / 実行中 |
| マージ・修正 | 待機 |
```

### 5. レビュー結果のマージ・分析

3つのレビューファイルを Read ツールで読み込み、以下の方針で 3-way マージする:

#### マージ優先度

| 指摘元 | 信頼度 | 扱い |
|---|---|---|
| 3者共通 | 最高 | 最優先で対応 |
| 2者共通 | 高 | 対応推奨 |
| サブエージェントのみ | 中 | 標準的な指摘として妥当性を評価 |
| Codex review のみ | 中 | 組み込みレビューロジック固有の発見として評価 |
| adversarial のみ | 中〜高 | 攻撃的スタンスならではの発見、根拠を確認して判断 |

#### マージ手順

1. **3者共通の指摘**: 最高優先度として統合
2. **2者共通の指摘**: 高優先度として統合、どの2者かを記録
3. **単独の指摘**: 内容を精査し、根拠が十分であれば採用
4. **矛盾する指摘**: 3者の根拠を比較し、コード文脈を確認した上でより妥当な方を採用
5. **重複の統合**: 同一箇所への重複指摘を1つにまとめる

### 6. マージ結果の提示とユーザー確認

統合したレビュー結果をユーザーに提示する:

```markdown
| # | ファイル | 重要度 | 内容 | 指摘元 | 対応方針 |
|---|---------|--------|------|--------|----------|
| 1 | path/to/file.go:42 | Critical | 説明 | 3者共通 | 修正する |
| 2 | path/to/file.go:80 | Warning | 説明 | {ai_name}+adversarial | 修正する |
| 3 | path/to/file.go:55 | Warning | 説明 | Codex review | 修正する |
| 4 | path/to/file.go:100 | Info | 説明 | adversarial | スキップ — 理由 |
```

AskUserQuestion でユーザーに確認を取る:
- どの指摘に対応するか（multiSelect）
- 対応方針の変更があるか

**重要**: ユーザーの確認なしにコード修正を行わない。

### 7. 修正の適用

ユーザーが承認した指摘について修正を実施する:

1. 対象ファイルを Read → Edit で修正
2. 対象ファイルの言語に応じた lint/test を実行
3. テストが失敗した場合は原因を分析し、修正を再試行

### 8. 結果の報告

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
- **サブエージェントの prompt に差分内容を埋め込まない**。サブエージェント自身に diff コマンドを実行させる

### 実行ルール

- 3チャネルは必ず**並列で**起動すること（同一ターン内で全ての呼び出しを行う）
- `codex:review` / `codex:adversarial-review` は `disable-model-invocation: true` のため **Skill ツールから呼び出せない**。`codex-companion.mjs` を Bash で直接実行すること
- `codex-companion.mjs` のパスは `find ~/.claude/plugins -path "*/codex/scripts/codex-companion.mjs" -type f` で動的に解決する（plugin 更新でパスが変わる可能性があるため）
- `codex:review` は組み込みレビューAPI を使用し、カスタム観点を受け付けない。Codex 側の判断に任せる
- `codex:adversarial-review` は focus text で10観点を渡せる。ユーザーの追加指示もここに含める

### マージ・修正ルール

- レビュー結果のマージはユーザーに提示してから修正に入る
- 3者の指摘が矛盾する場合は、コードの文脈を確認した上で判断理由を明記する
- **`--target staged` の場合**: Codex チャネルは working-tree でレビューするため、unstaged ファイルへの指摘が混入する。マージフェーズで `git diff --cached --name-only` の結果と照合し、staged ファイルに関する指摘のみを採用すること
