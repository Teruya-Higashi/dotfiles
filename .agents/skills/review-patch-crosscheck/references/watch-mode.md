# review-patch-crosscheck watchモード

PRまたはローカル差分の更新を監視し、安定した変更ごとにreview-patch-crosscheck本体を再実行する。監視を継続できない状態で「監視中」と表現しない。

watch中は起動時のフラグを事前確認済みとみなす。`--post`は選択済み媒体へ投稿する。`--fix`はPR以外ならcommitまで、自分の同一repository PRならcommit + pushする。PR + `--local`のforkだけcommit止まりを許し、他人PRと`--local`なしのfork PRは拒否する。併用時は修正を先に行い、解消した指摘を投稿しない。

## 駆動方式

watchの駆動は次に従う。

- loop / ScheduleWakeupあり: 起動時のコマンド名、引数、フラグ、明示locatorを一字一句維持して60秒後に自己再入する
- 代替: 同じassistant turn内で60秒以下の待機を繰り返す
- 禁止: detached/background processを監視継続とみなさない
- 状態: 毎tickでファイルから復元し、会話の記憶だけに依存しない
- エラー: 状態を進めず再試行する
- セッション終了: 状態を残し、監視停止を明示する
- 終了: 状態ファイルは削除せず、成功回数・reviewed snapshot・失敗理由・未確認範囲など既存の全 field を保持して phase だけ stopped に atomic rename する。明示的に新しい監視を開始するときは保存した結果と未確認範囲を提示してから実行単位のカウンターを初期化する。単なる読込み・停止では消去しない

GitHub監視用の`{repository-key}`は、canonicalなrepository common dirのSHA-256先頭16文字とし、各tickで再計算する。

## GitHub投稿を使うPR対象

状態パスの `codex-review-watch` は既存データとの互換名であり、Claude / Codex 共通で使う。

`--local`なしのPR監視だけに適用する。状態は`${TMPDIR:-/tmp}/codex-review-watch/{repository-key}/review-patch-crosscheck-{PR番号}.json`へ保存する。親directoryを`0700`で作り、private temporary JSONを検証してatomic renameする。リポジトリ内へfallbackしない。初回は`gh pr view {PR} --json author,headRefOid,updatedAt,state`を取得して即時レビューする。

```json
{"reviewedSha":"", "candidateSha":"", "runCount":0}
```

各tickでPRがOPENであることとheadRefOidを確認する。reviewedShaと異なるSHAをcandidateShaへ保存し、次tickでも一致したときだけ発火する。発火直前にもOPENかつ同じSHAか確認する。MERGED/CLOSEDなら実行回数と未処理結果を報告し、状態ファイルをstoppedへ上書きして終了する。

安定した新HEADでは次を出力してから、専用worktree作成、full PR diffを使う全チャネル並列レビュー、マージ、修正・投稿確認、cleanupまで本体の全手順を実行する。増分diffだけを対象にしない。

```text
PR {PR} の新しい HEAD を確認しました: {reviewedSha短縮} → {candidateSha短縮}
full PR diff を対象に review-patch-crosscheck を実行します。監視は処理後に継続します。
```

初回を含め、non-postではmerged結果の提示、`--fix`ではpushまたはcommit、`--post`では投稿APIの反映まで確認し、全処理成功後だけreviewedShaを進める。失敗時はcandidateを残す。

## `--local`対象

`--local`では開始前に`../../review-patch/references/local-review-mode.md`を読み、ローカル差分のreview ID、review directory、locatorを固定する。状態は`{review-directory}/review-watch.json`へprivate temporary JSONからatomic renameする。GitHub投稿用のOS一時状態は併用しない。

```json
{"phase":"watching|stopped", "reviewedValue":"", "candidateValue":"", "runCount":0}
```

監視値は`pr`、`pr:{base}`、`staged`、`working`、`pr-number`ごとに確定したdiff commandの出力byte列のSHA-256とする。`set -o pipefail`を有効にし、diff commandが非ゼロ終了ならfingerprintを採用せず状態を進めない。現在時刻や生成物pathを入力に含めない。

`pr-number`はdiff fingerprintに加えてPR headを監視する。

- 各tickで`gh pr view {n} --json headRefOid,state`を取得する。`gh`や`git`がコマンド失敗したとき（networkが閉じたsandboxを含む）はPR状態を判定不能として扱い、`closed`更新とworktree削除は行わず報告して次tickへ進む。取得できて`state`がOPENでなければ実行回数と未処理結果を報告し、watch stateをstoppedへ上書き、manifestを`closed`へ更新、worktreeを`git worktree remove`で削除して終了する
- headRefOidがworktree HEADと異なる場合は、base refと`refs/pull/{n}/head`を一意なtemporary refへfetchし、取得headがheadRefOidと一致することを検証する。dirty変更・未commit修正・未push commitがあれば追従せず報告し、cleanな場合だけ専用detached worktreeを完全head SHAへ更新してfingerprintを計算する。remote-tracking refへfallbackしない
- 自分の`--fix` pushで進んだHEADは処理成功時にreviewedValueへ反映し、再発火させない

1. reviewedValueと同じなら次tickへ進む。
2. 新しい値をcandidateValueへ保存し、2 tick連続一致したときだけ発火する。
3. 発火直前に再計算する。`staged` / `working`はその同じbyte streamを0600の固有名private patchへ固定し、candidateValueと一致するSHA-256を確認して、そのpatchだけを全チャネルへ渡す。他targetはimmutable SHAのfull targetを使う。
4. `--post`ではlocal-review-modeの手順でfinding eventとreview-run eventを書く。直前runと同じ論点で内容も同じfindingは既存のfinding event IDを載せ、内容変更または解消後の再発は新しいfinding eventを書く。消えたfindingはresolved eventを書く。
5. 投稿・resolve直前にも同じtargetのfingerprintを確認する。`staged` / `working`はprivate patchと同一byte streamであることも確認し、不一致なら結果を破棄して次tickへ戻る。
6. non-postではmerged結果の提示またはcommit完了、postではreview-runの`event put`成功後だけreviewedValueを更新し、candidateを空にしてrunCountを増やす。

consumer replyはdiff fingerprintと別に毎tick監視する。

- 取得: 正本eventをグローバルmise taskの`reduce`で読む
- 起動前検査: raw reduce JSONを表示・会話contextへ載せず、`jq -c`で`replied-unresolved` threadの`finding_id`、`finding_event_id`、`tail_event_id`だけへ射影した出力を機械的に検査する。本文は表示・分析・各チャネルへ共有しない
- 発火: 未処理replyがあればdiff不変でも同じfull targetを全チャネルで再レビューする
- マージ後: 本文を取得し、findingを再判定する
- 応答: `reviewer-reply` eventを正本へ保存する
- 処理済み: `reduce`の`state`が`replied-unresolved`のthreadだけを対象にし、reviewer-replyかresolvedを書いた後は対象から外れる。別の処理済み一覧は持たない
- 自己発火防止: 自分のreviewer-replyでは再発火しない

安定した更新を確認した時点で、対象種別とreviewedValueからcandidateValueへの変化を出力し、full targetを全チャネルで再レビューすることを明示する。レビュー結果は通常実行と同じmerged形式で提示する。

ローカル差分はユーザーがwatch終了を指示したとき、または`--rounds`の終了条件を満たしたときにwatch stateをstoppedへ上書きする。manifestは別セッションからの返信に必要なためactiveのまま残す。

## 回数指定（`--rounds N`）

`--rounds N`は`--post`必須で watch を自動付与する。上限 N は起動引数から読み、自己再入でコマンド名・引数を一字一句維持する。状態は既存の `runCount` と snapshot を使う。

- 初回を含め、本体のレビュー、必要な fix の commit / push、投稿と反映確認まで完了した 1 回をラウンドとする。GitHub では `reviewedSha` と同時に runCount を 1 増やす。ローカルでは review-run の put・reduce 照合成功後に増やす。状態更新は同じ private JSON の atomic rename で確定する。
- 投稿失敗、snapshot 不一致による破棄、consumer reply への再判定だけでは加算しない。上限に達した状態を復元したら本体を再実行せず終了する。
- `runCount >= N`なら次 tick を予約せず、実行回数・最終結果を報告して stopped を保存する。ローカル manifest は active のまま残す。
- 統合・重複排除後の指摘が 0 件で、失敗チャネルも未走査境界もない のラウンドは、数えた上で N 未満でも正常収束として終了する。
- `--fix`ですべて解消して投稿候補が 0 件になった場合は正常収束ではない。marker を付けず通常のラウンドとして数える。

指摘 0 件でも失敗チャネルまたは未走査境界が残る場合は、正常収束 marker を付けず、成功回数も reviewedSha / reviewedValue も進めない。失敗理由と未確認の範囲を state に保持して停止し、実行回数は完了済みの成功回数だけを報告する。

正常収束したラウンドは投稿を省略しない。

| 媒体 | 収束通知 |
|---|---|
| GitHub | 「指摘なし」の COMMENT レビューを、レビューした head SHA の `commit_id` 付きで投稿し、本文末尾の独立行に `<!-- review-rounds:converged:{headRefOid} -->` を 1 個付ける |
| ローカル | `findings: []` の review-run を最後に put し、body の末尾の独立行に `<!-- review-rounds:converged:{diff_fingerprint} -->` を 1 個付ける |

marker の SHA / fingerprint は投稿直前に再照合した snapshot の値だけを使う。部分失敗や通常の「未返信なし」に付けない。consumer が停止・収束を取り違えないよう、正常収束でない空 run には marker を付けない。

例: `/review-patch-crosscheck 123 --rounds 3 --post`。`--rounds`を指定しない watch の継続・承認条件は従来どおりとする。
