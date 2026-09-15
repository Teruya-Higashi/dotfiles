# マージ・結果提示・完了報告

## マージ

全チャネル完了後に採用可能な出力を初めて読む。PR指定時はここでPR本文、コミットメッセージ、`closingIssuesReferences`を取得し、各linked issueの本文と全コメントを読む。レビュー本文、インラインコメントと返信、PR会話コメントはそれぞれのAPI endpointからページネーション付きで全件取得する。変更意図を知れば解消する`ask`、作者が回答済みの論点、既存指摘との重複を除外する。

`{review_patch_skill_dir}/references/review-policy.md`と`{review_patch_skill_dir}/references/output-and-actions.md`を読み、各候補の差分起因性、対象外ファイル、根拠、actionable性を再検証する。

- 表現が異なる同一論点は、発火条件、影響、修正方針でまとめる。行番号だけの違いでは別件にしない
- 各指摘には検出した全チャネルを記録する
- 一致数は調査順序であり、正しさの投票ではない
- 同じモデル由来の相関誤りを考慮し、到達可能な発火条件とコード上のevidenceで判断する
- 同一箇所に複数観点が交差する場合は複合影響を検討し、必要ならseverityを上げる

| 独立チャネル一致数 | 扱い |
|---:|---|
| 3〜4 | 最優先でevidenceを検証 |
| 2 | 高優先でevidenceを検証 |
| 1 | 固有指摘として同じ基準で検証 |

adversarialの`Critical` / `Warning` / `Info`やnative reviewのseverityは機械変換せず、`review-patch`の基準で`critical` / `should` / `nits` / `ask`を決め直す。

### 境界カバレッジ監査

マージ担当が4チャネル出力を読んだ後、次の集合を作る。

1. `expected`: 差分と各Censusの「変えた契約」から、契約が到達する具体境界を独立に数え上げた基準集合。DB書込み、オブジェクトキー、CLI再送など具体単位にし、「永続化」のようなカテゴリ名で止めない。「未走査の境界」も含める
2. `covered`: 各Boundary Censusの「指摘なしの境界」「指摘のある境界」の和集合。「未走査」は含めない
3. `uncovered`: `expected - covered`

集合は文字列一致ではなく意味で突合し、表記が違っても同じ具体境界なら走査済みとする。カテゴリ名だけの報告は配下の具体境界をcoverしない。Census欠落チャネルは`covered`から除くだけでチャネル失敗にしない。

`uncovered`があれば[`channel-prompts.md`](channel-prompts.md)のboundary-followupへ全境界名をまとめて渡し、1回だけ実行する。

- 他チャネルの本文・候補は渡さない
- findingは通常基準と既存レビュー重複排除を通し、検出元`boundary-followup`として統合する。一致数には加えず、固有指摘と同じ基準で検証する
- `No findings.`を含む成功では対象境界を走査済みとして記録する
- 非ゼロ終了、空出力、形式不正、静的レビュー契約違反は失敗。再試行・再監査はせず、理由を未走査として残す
- 未走査境界が1つでも残る場合、判定を`APPROVE`にしない

`{prefix}-merged_{seq}.md`へ次の構造で全文を書き、同じ全文を省略・要約せず会話へ提示する。

```markdown
## レビューサマリー

**変更の意図**: ...
**影響範囲**: ...

### 境界カバレッジ

| 境界 | 走査チャネル |
|---|---|
| ... | rules-agent, senior-codex |
| ... | boundary-followup |
| ... | —（未走査: {失敗理由}） |

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
- 対応判定: **対応推奨 / 対応不要 / 要確認** — ...
```

各指摘の詳細には、問題、具体的な発火条件、根拠、影響、修正案、対応判定を含める。指摘ゼロかつ未走査境界がなければAPPROVEとし、「指摘なし」、変更意図、影響範囲を記載する。

会話とローカル成果物ではテキストバッジを使う。GitHub投稿時だけ`review-patch`の規則に従って画像バッジへ変換する。

## 結果提示と修正

`--local`ではauthorに関係なくGitHub投稿フローへ入らず、review directoryの正本eventへの投稿だけを行う。他メンバーのPRでは修正を拒否する。`--local`なしのPRはauthorを確認し、他メンバーなら修正フローに入らず`review-patch`のGitHub投稿フローへ進む。投稿は事前確認を取り（`--post`指定時は省略）、本文から「指摘元」列とレビュー体制の説明を除く。

authorが自分のPR、またはPR番号を伴わないローカル指定なら次だけを確認する。

```text
修正しますか？（all / 番号指定 / none）
```

`--fix`指定時はこの確認を行わず、critical / shouldを選択済みとして扱う。それ以外は確認前にファイルを変更しない。選択された指摘だけ対象ファイルを改めて読み、修正する。検証は`AGENTS.md` / `CLAUDE.md`、プロジェクト文書、task runner定義を確認し、対象に対応する既定タスクを優先する。直接コマンドしかなければ変更に対応する最小のlint / test / build / codegenを実行する。

`--local`の`staged` / `working`はpostの有無を問わず、結果提示とファイル変更の直前にprivate patch hashとlive target fingerprintを照合する。不一致なら編集・commitせず、新snapshotで4チャネルから再レビューする。

- 選択された対応hunkだけをstageする
- `staged`は実行時点のindexと選択した修正だけ、`working`は実行時点のtracked差分と選択した修正だけをcommitし、untracked fileを含めない
- 既存unstaged hunkと安全に分離できなければcommit前に停止する
- PR以外はcommit後もpushしない
- PR対象は自分のPRだけ修正する。`--local`なしは同一repositoryだけcommit + pushし、forkでは`--fix`を拒否する。`pr-number`は同一repositoryならpushし、forkならcommitまでで止める

`--local --target staged|working --fix --post`はpost-fix snapshotへ明示的に遷移する。

1. 修正前にprivate patch hashとlive target fingerprintの一致を確認する
2. 選択範囲をcommitし、`pre_fix_head..post_fix_head`の完全SHA diffをpost-fix targetとして生成する
3. 生き残る指摘をpost-fix targetで再検証し、post-fix HEAD、fingerprint、finding payloadを固有名private fileへ保存する
4. 投稿直前に同じ完全SHA diffのfingerprintを再計算し、一致した場合だけ投稿する。元patch hashとの一致は要求しない

`--local`の投稿はmerged検証後だけ行う。本文からチャネル名・一致数・レビュー体制を除き、`--post`なしでは承認後、`--post`ありでは直ちに正本eventへ投稿する。review-runを最後に`event put`し、`reduce`の再取得で確認してからreview IDと`/reply-pr-review --local {review ID}`を提示する。書込み失敗時はmanifestを変更しない。local watchのreply発火では、起動前は`reduce`が返す`replied-unresolved` threadのevent IDだけを機械検査し、本文はマージ後に読む。

PR番号・URL指定でレビューだけを行った場合は、`{artifact_dir}`がworktree外にあること、各成功チャネルの採用出力、merged、timing logが存在して非空であることを再検証してから、Serena 等を元の絶対パスへ戻し、自分が作成した専用worktreeと一時refだけを削除する。修正でworktreeがdirtyなら削除・force removeせず、pathを報告して保存・転送方法を確認する。PR番号 + `--local`ではactive manifestがworktreeを使うため削除せず、closedまたはPR終了時だけshared local-review-modeに従って削除する。

ユーザー添付メディアを GitHub へ投稿する場合は `review-patch` の GitHub 投稿節と、そこから参照する添付手順に従う。`--post` だけで添付を承認済みとせず、承認済み companion comment の URL を使う。`--local` では GitHub 添付を行わない。

## 完了報告

対応した指摘、スキップした指摘と理由、検証結果、`{artifact_dir}`の絶対パス、各チャネルの経過秒と生存した固有指摘数を報告する。boundary-followupを実行した場合は経過秒と固有指摘数も含める。失敗チャネルがあれば通常の4チャネル統合ではなく暫定結果であることを明記する。論理チャネル数は常に4で、followupは派生チャネル、再試行は失敗チャネルの別attemptとして扱う。commit、push、GitHub投稿はユーザーが明示的に依頼・承認した場合だけ行う（`--fix` / `--post`指定時はフラグ指定を承認とみなす）。

rules-agent が最遅の場合は timing log のフェーズ別内訳も報告する。実行主体（Claude / Codex）と明示指定モデルを記録し、同じモデル由来の結果を異種モデルの合意と説明しない。フェーズの欠測は未計測と記す。
