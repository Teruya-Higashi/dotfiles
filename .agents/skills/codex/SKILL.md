---
name: codex
description: Codex にタスクを依頼する。タスク内容を引数に取る。
---

# Codex タスク委任スキル

Codex（OpenAI のコーディングエージェント）に `codex exec` CLI 経由でタスクを委任するスキル。
plugin（`codex:rescue`）は経由せず、`codex` バイナリを Bash から直接呼び出す。

## 前提

- `codex` CLI がインストール済みであること（`which codex` で確認）
- 認証・モデル・サンドボックス設定は `~/.codex/config.toml` に従う
  - 想定: `approval_policy = "never"`, `sandbox_mode = "workspace-write"`（非対話で自律実行できる設定）
  - config が未整備の場合は `codex login` 等をユーザーに案内する

## 引数

```
/codex [タスクの説明]
```

- **タスクの説明**: Codex に実行させたいタスクの内容（必須）

## オプション

引数内に以下のキーワードが含まれる場合、対応するパラメータを切り替える。
指定がなければデフォルト値を使用する。

| オプション | デフォルト | 選択肢 | 引数内キーワード例 |
|---|---|---|---|
| モデル | `gpt-5.5` | `gpt-5.5`, `gpt-5.4` 等（codex が解決できるモデル名） | `--model gpt-5.4` |
| effort | `xhigh` | `none`, `minimal`, `low`, `medium`, `high`, `xhigh` | `--effort high` |
| 出力ファイル | なし | 任意のファイルパス | `--output ./review.md` |
| 実行モード | foreground | `--background`, `--wait` | `--background` |
| スレッド | 新規 | `--resume`, `--fresh` | `--resume` |

**パース規則**:
- `--model {値}`, `--effort {値}`, `--output {値}`, `--background`, `--wait`, `--resume`, `--fresh` を引数から抽出し、残りをタスクの説明として扱う
- キーワードが見つからなければデフォルト値（`--model gpt-5.5 --effort xhigh`）を使用

## Codex CLI へのマッピング

抽出したオプションを `codex exec` のフラグに変換する。

| スキルのオプション | `codex exec` フラグ | 備考 |
|---|---|---|
| `--model {値}` | `-m {値}` | 指定値をそのまま渡す（未指定時は `gpt-5.5`） |
| `--effort {値}` | `-c model_reasoning_effort="{値}"` | config の `model_reasoning_effort` を上書き（未指定時は `xhigh`） |
| `--output {値}` | `-o {値}` | エージェントの最終メッセージをファイルに書き出す |
| `--resume` | `codex exec resume --last` を使用 | 直近セッションを継続 |
| `--fresh` | 新規 `codex exec`（デフォルト） | 追加指示でも新規スレッドにする |
| `--background` | Bash ツールの `run_in_background: true` | CLI 側のフラグではなく実行制御 |
| `--wait` | フォアグラウンド実行（デフォルト） | 完了まで待つ |

**プロンプトの渡し方**: 多行・特殊文字を安全に渡すため、プロンプトは引数ではなく heredoc で stdin から渡す（`codex exec` は PROMPT 省略時 stdin を読む）。

```bash
codex exec -m {model} -c model_reasoning_effort="{effort}" - <<'EOF'
{タスクの説明}
EOF
```

`--output` 指定ありの場合は `-o {出力ファイル}` を追加する:

```bash
codex exec -m {model} -c model_reasoning_effort="{effort}" -o ./review.md - <<'EOF'
{タスクの説明}
EOF
```

`-o` はエージェントの**最終メッセージ**をファイルに書き出す。全文を残したい場合はプロンプト末尾に
「最終応答として結果の全文を出力すること（要約しない）」と明示する。

## 手順

### 1. タスク内容の確認

引数からタスクの説明とオプションを取得する。引数が空の場合は AskUserQuestion でタスク内容を確認する。

### 2. codex exec の呼び出し

オプションを CLI フラグに変換し、Bash ツールで `codex exec` を実行する。

- `--background` 指定時: Bash ツールを `run_in_background: true` で起動し、完了通知を待つ
- `--wait` 指定時 / 未指定時: フォアグラウンドで実行し、完了まで待つ
- `--resume` 指定時: `codex exec` の代わりに `codex exec resume --last` を使う（フラグ構成は同じ）

```bash
# 新規スレッド
codex exec -m {model} -c model_reasoning_effort="{effort}" [-o {output}] - <<'EOF'
{タスクの説明}
EOF
```

```bash
# スレッド継続（--resume）
codex exec resume --last -m {model} -c model_reasoning_effort="{effort}" [-o {output}] - <<'EOF'
{追加指示}
EOF
```

### 3. 結果の確認

`codex exec` の stdout（および `-o` 指定時は出力ファイル）を受け取り、ユーザーに報告する:
- 成功した場合: 変更内容のサマリーを報告
- 失敗した場合: stdout/stderr のエラー内容と終了コードを報告し、次のアクションを提案
- Codex の出力は加工せず、そのまま伝える

### 4. フォローアップ（必要に応じて）

追加指示がある場合は `codex exec resume --last` で同一スレッドを継続する。
前回の文脈を引き継いで作業を続けられる。

```bash
codex exec resume --last -m {model} -c model_reasoning_effort="{effort}" - <<'EOF'
{追加指示}
EOF
```

## 注意事項

- ユーザーの依頼内容を変えずにそのまま Codex に委任すること。事前に情報を収集・加工して prompt に含めない
  - 例: レビュー依頼の場合、差分の取得も Codex 自身に行わせる（呼び出し側で `git diff` して結果を渡さない）
  - 例: バグ調査の場合、関連ファイルの読み取りも Codex に任せる（呼び出し側で事前にファイルを読まない）
- 承認・サンドボックスは `~/.codex/config.toml` の設定に従う。非対話実行のため `approval_policy = "never"` を前提とする
  - config が `never` でない環境では `codex exec` がプロンプト待ちで停止しうる。その場合はユーザーに config 設定を案内する
- Codex の変更内容は `git diff` で確認し、意図しない変更がないかレビューする
- 大規模な変更を依頼する場合は、タスクを分割して段階的に実行する
- レビュー専用のタスクには `codex exec review`（`--uncommitted` / `--base {branch}` / `--commit {sha}`）の利用も検討する
