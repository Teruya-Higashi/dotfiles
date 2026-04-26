---
name: codex
description: Codex にタスクを依頼する。タスク内容を引数に取る。
---

# Codex タスク委任スキル

Codex（OpenAI のコーディングエージェント）に codex plugin（`codex:rescue` コマンド）経由でタスクを委任するスキル。

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
| モデル | `gpt-5.5` | `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex`, `spark` 等 | `--model spark` |
| effort | `xhigh` | `none`, `minimal`, `low`, `medium`, `high`, `xhigh` | `--effort high` |
| 出力ファイル | なし | 任意のファイルパス | `--output ./review.md` |
| 実行モード | (plugin デフォルト) | `--background`, `--wait` | `--background` |
| スレッド | 新規 | `--resume`, `--fresh` | `--resume` |

**パース規則**:
- `--model {値}`, `--effort {値}`, `--output {値}`, `--background`, `--wait`, `--resume`, `--fresh` を引数から抽出し、残りをタスクの説明として扱う
- キーワードが見つからなければデフォルト値（`--model gpt-5.5 --effort xhigh`）を使用

**出力ファイルの扱い**:
- `--output` が指定された場合、タスクのプロンプト末尾にファイル書き出し指示を埋め込む
- plugin 側に `-o` 相当のフラグがないため、Codex 自身のファイル操作で書き出させる

## 手順

### 1. タスク内容の確認

引数からタスクの説明とオプションを取得する。引数が空の場合は AskUserQuestion でタスク内容を確認する。

### 2. codex:rescue コマンドの呼び出し

`codex:rescue` コマンドに委譲する。このスキルはパラメータの変換と `--output` の処理のみを行い、Codex の実行制御は plugin に任せる。

**`--output` 指定なしの場合**:

```
Skill(
  skill: "codex:rescue",
  args: "{routing_flags} {タスクの説明}"
)
```

**`--output` 指定ありの場合**:

プロンプト末尾にファイル書き出し指示を追加する:

```
Skill(
  skill: "codex:rescue",
  args: "{routing_flags} {タスクの説明}

重要: 結果の全文を {出力ファイル} にファイル操作で直接書き出してください。要約ではなく、全セクション・全指摘を省略せずに記載すること。"
)
```

**routing_flags の構築**:
- `--model {値}` → そのまま渡す（未指定時は `--model gpt-5.5`、`spark` は plugin が `gpt-5.3-codex-spark` にマッピング）
- `--effort {値}` → そのまま渡す（未指定時は `--effort xhigh`）
- `--background` / `--wait` → そのまま渡す
- `--resume` / `--fresh` → そのまま渡す
- `--output` → routing_flags には含めない（プロンプトに埋め込む）

### 3. 結果の確認

`codex:rescue` の実行結果を受け取り、ユーザーに報告する:
- 成功した場合: 変更内容のサマリーを報告
- 失敗した場合: エラー内容を報告し、次のアクションを提案
- plugin の `codex:codex-result-handling` ガイダンスに従い、結果をそのまま伝える

### 4. フォローアップ（必要に応じて）

追加指示がある場合は `--resume` フラグを付けて再度 `codex:rescue` を呼び出す。
plugin がスレッド管理を行うため、前回の文脈を引き継いで作業を継続できる。

```
Skill(
  skill: "codex:rescue",
  args: "--resume {追加指示}"
)
```

## 注意事項

- ユーザーの依頼内容を変えずにそのまま Codex に委任すること。事前に情報を収集・加工して prompt に含めない
  - 例: レビュー依頼の場合、差分の取得も Codex 自身に行わせる（呼び出し側で `git diff` して結果を渡さない）
  - 例: バグ調査の場合、関連ファイルの読み取りも Codex に任せる（呼び出し側で事前にファイルを読まない）
- Codex の変更内容は `git diff` で確認し、意図しない変更がないかレビューする
- 大規模な変更を依頼する場合は、タスクを分割して段階的に実行する
- レビュー専用のタスクには `/codex:review` や `/codex:adversarial-review` コマンドの直接利用も検討する
