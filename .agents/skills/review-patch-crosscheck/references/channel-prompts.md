# Review Patch Crosscheck: Channel Prompts

このファイルは`review-patch-crosscheck`の手順2で全文を読み、4チャネルのプロンプトを組み立てるためのテンプレートである。`{...}`は実行時の具体値に置換する。他チャネルの情報を渡さない。

## 共通変数

| 変数 | 内容 |
|---|---|
| `{workdir}` | レビュー対象リポジトリの絶対パス |
| `{artifact_dir}` | レビュー成果物を保存する絶対パス |
| `{diff_command}` | 全チャネル共通の差分取得コマンド |
| `{output}` | `{artifact_dir}`配下のチャネル固有の絶対出力パス |
| `{timing}` | timing logの絶対パス |
| `{model}` | Codexモデル |
| `{effort}` | reasoning effort |
| `{additional_instructions}` | 全チャネル共通の追加レビュー指示。指定なしなら空 |
| `{start}` | 呼び出し元が記録した開始epoch秒 |
| `{attempt}` | 1または2の試行番号 |

## 静的レビュー契約

以下を4チャネルすべてへそのまま渡す。

```text
<static-review-contract>
あなたの仕事は指定差分の静的レビューだけです。指定されたレビュー出力以外は、レビュー対象のリポジトリと、その外部にある状態を一切変更しないでください。

許可:
- 読み取り専用のファイル閲覧、検索、git/ghの参照系コマンド
- 変更の意図、呼び出し元、依存先、既存テスト、プロジェクト規約の調査

禁止:
- 指定されたレビュー出力以外のファイル作成・編集・削除・format
- git add / commit / push / checkout / switch / rebase / reset / clean / stash
- GitHubへの投稿・編集・close・merge・review
- lint / test / build / codegenと、それらを起動するtask runner
- パッケージ導入、依存更新、ネットワーク上の状態変更
- ユーザーへの確認、修正の適用

各指摘は差分に起因する問題だけを対象にし、ファイルと行、具体的な発火条件、コード上の根拠、影響、実行可能な修正案を示してください。候補ごとに反証を試み、推測だけの指摘、formatterが処理するスタイル、変更と無関係な既存問題、自動生成ファイルへの指摘を除外してください。問題がなければ明確に「指摘なし」としてください。

最終出力の末尾に「検証: 静的確認のみ（テスト・lint・build未実行）」と明記してください。
</static-review-contract>
```

## `review-patch`実行指示

rules-agentとrules-codexへ静的レビュー契約に加えて渡す。

```text
<review-patch-instructions>
`~/.agents/skills/review-patch/SKILL.md`を全文読み、そのレビュー方針を適用してください。ただし次を上書きします。

- 差分範囲とworktreeは呼び出し元が確定済みなので、引数解釈やworktree作成は行わない
- 独立チャネルとして実行中なので、変更規模を理由に別スキルを提案して停止しない
- インラインモードでコンテキスト収集、レビュー、Validation、フィルタリングを完遂する
- GitHub投稿、ファイル修正、テスト実行、ユーザー確認、worktree cleanupは行わない
- ローカル向けテキストバッジ`[critical]` / `[should]` / `[nits]` / `[ask]`を使う
- 最終結果全文を指定された方法で返す
</review-patch-instructions>
```

## Codexチャネル共通指示

senior-codex、adversarial-codex、rules-codexへ渡す。

```text
Codex CLIから利用できない専用ツールを前提にしないでください。`AGENTS.md`、変更対象に対応する`.agents/skills`やリポジトリ内の規約を直接読み、影響範囲は`rg`、`git grep`、読み取り専用コマンドで調査してください。規約名やパスを推測せず、`rg --files`で存在を確認してください。
```

## 対象指定

4チャネルへ同じブロックを渡す。`{diff_command}`自体に`cd`を含めない。

```text
<review-target>
作業ディレクトリ: {workdir}
レビュー対象は次のコマンドが出力する差分だけです。

{diff_command}

このコマンドの出力と、問題の裏取りに必要な周辺コードだけを読んでください。
</review-target>
```

追加指示がある場合だけ、各チャネルの末尾へ同じ内容を渡す。静的レビュー契約と矛盾する内容は展開前に拒否する。

```text
<additional-review-instructions>
{additional_instructions}
</additional-review-instructions>
```

## チャネル1: rules-agent

利用可能なサブエージェント機能を通常の権限制約のまま使い、権限バイパスを指定せずバックグラウンド起動する。read-only sandboxを指定できる実行環境では必ず指定する。プロンプトは「静的レビュー契約 → 対象指定 → review-patch実行指示 → 次の固有指示」の順で連結する。

```text
あなたはプロジェクト規約に精通したコードレビュアーです。review-patchのレビュー工程を完遂し、候補をevidenceと敵対的反証で検証してから、レビュー全文を最終応答として返してください。ファイルは一切変更しないでください。すべてのコマンドとファイル参照は{workdir}を基準にし、絶対パスまたは`git -C "{workdir}"`を使ってください。
```

呼び出し元は最終応答を受け取り、静的レビュー契約と期待形式を検査してから`{output}`へ保存する。起動直前に`{start}`を記録し、完了通知時刻とともに次の1行を`{timing}`へ追記する。

```text
rules-agent,{attempt},{start},{end},{result}
```

## Codex実行テンプレート共通規則

- `--ephemeral -c 'approval_policy="never"' -c 'sandbox_mode="read-only"'`で静的レビュー契約を実行時にも強制する
- `approval_policy="never"`は承認待ちを起こさず、承認が必要な操作を拒否するために指定する
- read-only sandboxはモデルが実行するコマンドに適用され、CLI自身による`-o`への書き込みは許可される
- 終了コードは`rc`へ退避する。zshで読み取り専用の`status`へ代入しない
- `{workdir}` / `{output}` / `{timing}`は検証済みのcanonical pathだけを使う
- `-m {model} -c 'model_reasoning_effort="{effort}"'`を3チャネルで統一する
- 実値をshell sourceへ無検証で連結しない。workdirなど任意パスは実行ツールのargvまたはshell-safeにquoteした変数として渡す
- 以下のheredocは模式例である。実行時は完成したpromptに単独行として現れないdelimiterを生成・検査し、固定delimiterへユーザー入力を直接展開しない

## チャネル2: senior-codex

プロンプトは「静的レビュー契約 → 対象指定 → Codex共通指示 → 次の固有指示」の順で連結する。

```text
シニアエンジニアとしてこの変更をレビューしてください。正確性、セキュリティ、保守性、性能、テストを変更内容に応じて判断し、重要な順にfindingsを示してください。各findingにファイル、行、発火条件、根拠、影響、修正案を含め、最終回答だけを返してください。
```

```bash
start=$(date +%s)
cd "{workdir}" && codex exec review \
  --ephemeral \
  -c 'approval_policy="never"' \
  -c 'sandbox_mode="read-only"' \
  -m {model} \
  -c 'model_reasoning_effort="{effort}"' \
  -o "{output}" \
  - <<'EOF'
{prompt}
EOF
rc=$?
end=$(date +%s)
printf '%s,%s,%s,%s,%s\n' senior-codex "{attempt}" "$start" "$end" "$rc" >> "{timing}"
exit "$rc"
```

対象指定フラグと`-C`は付けない。`-o`の`{output}`だけを書き込み禁止の例外とする。

## チャネル3: adversarial-codex

プロンプトは「静的レビュー契約 → 対象指定 → Codex共通指示 → 次の固有指示」の順で連結する。

```text
あなたは敵対的コードレビュアーです。「正常に動く理由」ではなく「本番でどう壊れるか」から差分を検証してください。次の観点を変更内容に応じて調査し、該当しない観点は無理に指摘しないでください。

1. 境界値、空値、nil、ゼロ値、桁あふれ
2. エラーの握り潰し、誤分類、復旧不能
3. 競合、順序依存、再試行、冪等性
4. 認証、認可、入力検証、秘密情報
5. トランザクション、部分失敗、データ整合性
6. リソースリーク、無制限処理、性能劣化
7. API・型・スキーマの後方互換性
8. キャッシュ、鮮度、状態同期
9. 可観測性、診断可能性、障害時の情報欠落
10. テストが見逃す現実的な失敗経路

出力形式:

## Adversarial Review

### Findings
- [Critical|Warning|Info] `path:line` — 概要
  - Trigger: 具体的な入力・状態・実行順
  - Evidence: 到達するコードパス
  - Impact: 実害
  - Fix: 修正案

指摘がなければ`No findings.`とし、最終回答だけを返してください。
```

```bash
start=$(date +%s)
codex exec -C "{workdir}" \
  --ephemeral \
  -c 'approval_policy="never"' \
  -c 'sandbox_mode="read-only"' \
  -m {model} \
  -c 'model_reasoning_effort="{effort}"' \
  -o "{output}" \
  - <<'EOF'
{prompt}
EOF
rc=$?
end=$(date +%s)
printf '%s,%s,%s,%s,%s\n' adversarial-codex "{attempt}" "$start" "$end" "$rc" >> "{timing}"
exit "$rc"
```

## チャネル4: rules-codex

プロンプトは「静的レビュー契約 → 対象指定 → Codex共通指示 → review-patch実行指示 → 次の固有指示」の順で連結する。

```text
Codexとしてreview-patch skillを忠実に実行してください。レビュー候補をevidenceと敵対的反証で検証してから最終結果だけを返してください。出力ファイルへ直接書かず、レビュー全文を最終メッセージとして返してください。呼び出し元が`-o`で回収します。
```

```bash
start=$(date +%s)
codex exec -C "{workdir}" \
  --ephemeral \
  -c 'approval_policy="never"' \
  -c 'sandbox_mode="read-only"' \
  -m {model} \
  -c 'model_reasoning_effort="{effort}"' \
  -o "{output}" \
  - <<'EOF'
{prompt}
EOF
rc=$?
end=$(date +%s)
printf '%s,%s,%s,%s,%s\n' rules-codex "{attempt}" "$start" "$end" "$rc" >> "{timing}"
exit "$rc"
```

## 起動前チェック

テンプレート展開後、レビュー分析をせず次だけを機械的に確認する。

- 4つの`{diff_command}`が完全一致する
- 各`{output}`が異なり、すべて`{artifact_dir}`直下の絶対パスである
- 3つのCodexコマンドが同じ`{model}` / `{effort}`を使う
- 3つのCodexコマンドに`--ephemeral`、`-c 'approval_policy="never"'`、`-c 'sandbox_mode="read-only"'`がある
- `codex exec review`に`-C`と対象指定フラグがない
- 通常の`codex exec`に`-C "{workdir}"`がある
- 4チャネルすべてに静的レビュー契約が展開されている
- rules-agentとrules-codexにreview-patch実行指示が展開されている
- rules-agentが`{workdir}`基準でread-only動作し、最終応答を呼び出し元が`{output}`へ保存する
- 追加レビュー指示があれば4チャネルに同一内容が展開されている
- 各チャネルの出力契約に静的確認の必須フッターがある

確認後、4チャネルを同じターンでバックグラウンド起動する。
