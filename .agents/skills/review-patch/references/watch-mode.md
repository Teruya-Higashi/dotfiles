# review-patch watchモード

PR対象では`headRefOid`、`--local`のローカル差分ではdiff fingerprintを監視し、安定した変更ごとにreview-patch本体を実行する。監視を継続できない状態で「監視中」と表現しない。

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

GitHub監視用の`{repository-key}`は、canonicalなrepository common dirのSHA-256先頭16文字とする。同じリポジトリではworktreeを跨いで同じ値を再計算する。

## GitHub投稿を使うPR対象

状態パスの `codex-review-watch` は既存データとの互換名であり、Claude / Codex 共通で使う。

`--local`なしのPR監視だけに適用する。状態は`${TMPDIR:-/tmp}/codex-review-watch/{repository-key}/review-patch-{PR番号}.json`へ保存する。親directoryを`0700`で作り、private temporary JSONを検証してatomic renameする。リポジトリ内へfallbackしない。

```json
{"reviewedSha":"", "candidateSha":"", "runCount":0}
```

初回は`gh pr view {PR} --json author,headRefOid,updatedAt,state`を取得し、監視シグナルを待たず本体を実行する。non-postでは検証済み結果の提示、fix/postでは反映確認まで成功した後だけ、そのHEADを`reviewedSha`へ保存する。各tickでPRがOPENであることとheadRefOidを確認し、reviewedShaと異なるSHAをcandidateShaへ保存する。次tickでも一致したときだけ発火し、直前にもOPENかつ同じSHAか確認する。MERGED/CLOSEDなら実行回数と未処理結果を報告し、状態ファイルをstoppedへ上書きして終了する。

安定した新HEADでは次を出力してから、PR用worktree作成からcleanupまで本体をフル実行する。毎回full PR diffを対象にし、既存レビューとの重複も確認する。

```text
PR {PR} の新しい HEAD を確認しました: {reviewedSha短縮} → {candidateSha短縮}
full PR diff を対象に review-patch を実行します。監視は処理後に継続します。
```

`--fix`後はpushしたSHAのPR head反映、`--post`後は投稿APIの反映を確認し、全処理成功後だけreviewedShaを進める。失敗時はcandidateを残す。

## `--local`対象

`--local`では開始前に`local-review-mode.md`を読み、ローカル差分のreview ID、review directory、locatorを固定する。状態は`{review-directory}/review-watch.json`へprivate temporary JSONからatomic renameする。GitHub投稿用のOS一時状態は併用しない。

`range`は開始時に「consumer replyだけを監視し、差分更新では再レビューしない」と表示する。

`pr-number`はdiff fingerprintに加えてPR headを監視する。

- 各tickで`gh pr view {n} --json headRefOid,state`を取得する。`gh`や`git`がコマンド失敗したとき（networkが閉じたsandboxを含む）はPR状態を判定不能として扱い、`closed`更新とworktree削除は行わず報告して次tickへ進む。取得できて`state`がOPENでなければ実行回数と未処理結果を報告し、watch stateをstoppedへ上書き、manifestを`closed`へ更新、worktreeを`git worktree remove`で削除して終了する
- headRefOidがworktree HEADと異なる場合は、base refと`refs/pull/{n}/head`を一意なtemporary refへfetchし、取得headがheadRefOidと一致することを検証する。dirty変更・未commit修正・未push commitがあれば追従せず報告し、cleanな場合だけ専用detached worktreeを完全head SHAへ更新してfingerprintを計算する。remote-tracking refへfallbackしない
- 自分の`--fix` pushで進んだHEADは処理成功時にreviewedValueへ反映し、再発火させない

```json
{"phase":"watching|stopped", "reviewedValue":"", "candidateValue":"", "runCount":0}
```

監視値は確定したdiff commandの出力byte列のSHA-256とする。`set -o pipefail`を有効にし、`git diff`が非ゼロ終了ならfingerprintを採用せず状態を進めない。現在時刻や生成物pathを入力に含めない。

1. reviewedValueと同じなら次tickへ進む。
2. 新しい値をcandidateValueへ保存し、2 tick連続一致したときだけ発火する。
3. 発火直前にfingerprintを再計算し、immutable SHAのfull targetで本体を実行する。
4. `--post`ではlocal-review-modeの手順でfinding eventとreview-run eventを書く。直前runと同じ論点で内容も同じfindingは既存のfinding event IDを載せ、内容変更または解消後の再発は新しいfinding eventを書く。消えたfindingはresolved eventを書く。
5. 投稿・resolve直前にも同じfingerprintを確認する。不一致なら結果を破棄して次tickへ戻る。
6. non-postでは検証済み結果の提示またはcommit完了、postではreview-runの`event put`成功後だけreviewedValueを更新し、candidateを空にしてrunCountを増やす。

consumer replyはdiff fingerprintと別に毎tick監視する。

- 取得: 正本eventをグローバルmise taskの`reduce`で読み、`replied-unresolved` threadを選ぶ
- 発火: 未処理replyがあればdiff不変でもfindingを現在差分で再判定する
- 応答: `reviewer-reply` eventを正本へ保存する
- 処理済み: `reduce`の`state`が`replied-unresolved`のthreadだけを対象にし、reviewer-replyかresolvedを書いた後は対象から外れる。別の処理済み一覧は持たない
- 自己発火防止: 自分のreviewer-replyでは再発火しない

ローカル差分はユーザーがwatch終了を指示したとき、または`--rounds`の終了条件を満たしたときにwatch stateをstoppedへ上書きする。manifestは別セッションからの返信に必要なためactiveのまま残す。

## 回数指定（`--rounds N`）

`--rounds N`は`--post`必須で watch を自動付与する。上限 N は起動引数から読み、自己再入でコマンド名・引数を一字一句維持する。状態は既存の `runCount` と snapshot を使う。

- 初回を含め、本体のレビュー、必要な fix の commit / push、投稿と反映確認まで完了した 1 回をラウンドとする。GitHub では `reviewedSha` と同時に runCount を 1 増やす。ローカルでは review-run の put・reduce 照合成功後に増やす。状態更新は同じ private JSON の atomic rename で確定する。
- 投稿失敗、snapshot 不一致による破棄、consumer reply への再判定だけでは加算しない。上限に達した状態を復元したら本体を再実行せず終了する。
- `runCount >= N`なら次 tick を予約せず、実行回数・最終結果を報告して stopped を保存する。ローカル manifest は active のまま残す。
- Phase 3 の指摘のうち既存レビューと重複しないものが 0 件 のラウンドは、数えた上で N 未満でも正常収束として終了する。
- `--fix`ですべて解消して投稿候補が 0 件になった場合は正常収束ではない。marker を付けず通常のラウンドとして数える。

正常収束したラウンドは投稿を省略しない。

| 媒体 | 収束通知 |
|---|---|
| GitHub | 「指摘なし」の COMMENT レビューを、レビューした head SHA の `commit_id` 付きで投稿し、本文末尾の独立行に `<!-- review-rounds:converged:{headRefOid} -->` を 1 個付ける |
| ローカル | `findings: []` の review-run を最後に put し、body の末尾の独立行に `<!-- review-rounds:converged:{diff_fingerprint} -->` を 1 個付ける |

marker の SHA / fingerprint は投稿直前に再照合した snapshot の値だけを使う。部分失敗や通常の「未返信なし」に付けない。consumer が停止・収束を取り違えないよう、正常収束でない空 run には marker を付けない。

例: `/review-patch 123 --rounds 3 --post`。`--rounds`を指定しない watch の継続・承認条件は従来どおりとする。
