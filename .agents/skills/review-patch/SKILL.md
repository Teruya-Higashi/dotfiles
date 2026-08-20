---
name: review-patch
description: PR、ブランチ、コミット範囲、未コミット差分の通常コードレビューや、実装後のセルフレビューを依頼されたときに使用する。
---

# Review Patch

差分の表面だけでなく、変更の意図と影響範囲を理解し、根拠を検証してから指摘する。

**REQUIRED SUB-SKILL:** PR番号・URLを扱う場合や、GitHubからの情報取得・レビュー投稿で`gh`を使う場合は`gh-ops`を読む。

## 入力

引数でレビュー対象を指定する。省略時は現在のブランチのデフォルトブランチからの差分をレビューする。

| 引数 | 対象 | PR用worktree |
|---|---|---|
| PR番号 / 同一リポジトリのPR URL | PRの差分 | 作成する |
| ブランチ名 | `{base}...{branch}` | 作成しない |
| コミット範囲 | 指定範囲 | 作成しない |
| なし | `{base}...HEAD` | 作成しない |

デフォルトブランチは`git symbolic-ref refs/remotes/origin/HEAD`から解決し、取得できなければリポジトリ情報を確認する。根拠なく`main`へ固定しない。

### オプション（PR指定時のみ）

| オプション | 説明 |
|---|---|
| `--watch` | PRのコミット追加を監視し、pushごとにレビューを自動実行する |
| `--fix` | `--watch`専用。自分のPRに限りcritical / shouldを自動修正しcommit + pushまで行う |
| `--post` | `--watch`専用。発火ごとに検証済み指摘を確認なしでGitHubへ投稿する |

`--watch`指定時は[`references/watch-mode.md`](references/watch-mode.md)を全文読み、それに従う。

## Step 0: 対象の準備

PR指定時は[`references/pr-review-setup.md`](references/pr-review-setup.md)を全文読む。Step 0では同referenceの「PR情報」「正確なsnapshotの隔離」「差分」だけを実施する。要件収集はPhase 1、既存レビューとの重複排除はValidation後に実施する。

ローカル対象は次の差分を取得する。

| 対象 | 取得方法 |
|---|---|
| ブランチ | `git diff {base}...{branch} --stat`と`git diff {base}...{branch}` |
| コミット範囲 | `git diff {range} --stat`と`git diff {range}` |
| なし | `git diff {base}...HEAD --stat`と`git diff {base}...HEAD` |

refやrangeをshell sourceへ連結しない。引数として渡すか、Gitが受理する値であることを検証してshell-safeにquoteする。

## 3フェーズレビュー

### Phase 1: コンテキスト収集

レビュー前に1a〜1dをすべて収集する。独立した読み取りは可能な限り同じターンで並列tool callとして実行し、調査用サブエージェントは起動しない。

#### 1a. 変更の意図

PR本文、linked issueの本文とコメント、コミットメッセージを読み、「なぜ必要な変更か」を説明できる状態にする。PR以外では利用できる範囲のコミットメッセージとリポジトリ文書を使う。PR指定時の取得順序は`pr-review-setup.md`の「要件」を使う。

#### 1b. 影響範囲

変更された関数、型、インターフェース等の呼び出し元、参照元、依存先を追う。コードインデックスがあれば使い、なければ`rg`や`git grep`を使う。原則2 hopまでとし、指摘の裏取りに必要なら追加で追う。

#### 1c. 関連ルール

変更に関係する規約だけを選んで全文を読む。`AGENTS.md`、`CLAUDE.md`、`.claude/rules/`、`.agents/skills/`、言語・領域別skill、`CONTRIBUTING.md`、linter設定などを、実在を確認してから参照する。

#### 1d. テスト

変更に対応するテストが追加・更新されているか、既存テストへどのような影響があるかを静的に確認する。レビュー依頼だけではtest、lint、buildを実行しない。

Phase 1完了時に次を提示し、停止せずPhase 2へ進む。

```markdown
### コンテキスト収集結果
- **変更の意図**: ...
- **影響範囲**: ...
- **関連ルール**: ...
- **テスト**: ...
```

### Phase 2: 単一チャネルレビュー

メインエージェントが正確性、セキュリティ、設計・再利用、効率を1パスで直接レビューする。観点ごとに同じファイルを読み直さず、Phase 1のコンテキストを再利用する。

各候補を次の順で確認し、満たさないものは出力しない。

1. 変更前からある問題ではなく、差分に起因するか
2. 変更意図に照らして意図的な設計ではないか
3. 具体的な入力・状態、コードパス、結果を説明できるか
4. `critical` / `should`なら呼び出し元・参照元を実際に確認したか
5. プロジェクト規約、または確認できる実害に根拠があるか

変更規模や複雑さにより単一チャネルで安全に扱えない場合は、注意力を希釈したまま内部でレビューエージェントを増やさず、`review-patch-crosscheck`の利用を提案する。

### Phase 2.5: Validation

`critical` / `should`候補を2段階で検証する。`nits` / `ask`はStep 1の分類対象外だが、差分起因性と根拠は必要とする。

#### Step 1: Evidence分類

| 分類 | 基準 | 扱い |
|---|---|---|
| confirmed | 具体的なコード、行、発火条件が揃う | Step 2へ |
| likely | 根拠はあるが未確認の前提が残る | 前提を明記してStep 2へ |
| unconfirmed | コード根拠や発火条件がなく推測のみ | 除外 |

同じコンテキストで発火経路を再構成し、不足があれば読み取り・検索で追加確認する。それでも再構成できなければ除外する。

#### Step 2: 敵対的検証

confirmed / likely候補に対して、到達不能、前提誤り、仕様上正しい、影響過大の4観点で反駁を試み、実コードで確認する。

| 判定 | 基準 | 扱い |
|---|---|---|
| survived | 反駁後も到達可能で問題が実在する | Phase 3へ |
| weakened | 問題は実在するが影響が軽い | severityを下げてPhase 3へ |
| refuted | 到達不能、前提誤り、または仕様どおり | 除外 |

### Phase 3: フィルタリング

survived / weakened候補を得た後、PR指定時は`pr-review-setup.md`の「既存レビューとの重複排除」を実施する。残った候補を変更意図と影響範囲に照らし、本当に問題か、影響が正しいか、プロジェクト根拠があるか、actionableかを精査する。

次を除外する。

- 差分と無関係な既存問題
- プロジェクト規約に従っているコードへの指摘
- 変更意図を読めば解消する`ask`
- formatterやlintが機械的に検出するスタイル問題
- [`references/review-policy.md`](references/review-policy.md)の対象外ファイル
- プロジェクト内で許容され、規約にも実害にも根拠がない一般論
- 具体的な発火条件を書けない指摘

同じ箇所に複数の問題が交差する場合は複合影響を検討する。個別には`should`でも、組み合わせた実害により`critical`となる場合がある。

## 出力・投稿・レビュー後アクション

Phase 3後に[`references/output-and-actions.md`](references/output-and-actions.md)を全文読み、タグ、出力形式、指摘ゼロ時の扱い、GitHub投稿、修正確認、worktree cleanupに従う。

## 例

```text
/review-patch 5612
/review-patch 5612 --watch --fix
/review-patch https://github.com/owner/repo/pull/5612
/review-patch feature/foo
/review-patch abc123..def456
/review-patch
```

## 自己改善

繰り返し発生する偽陽性パターンを認識した場合、Phase 3のフィルタリング規則への追加をユーザーへ提案する。
