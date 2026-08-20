# watch モード（review-patch / review-patch-crosscheck 共通）

指定 PR へのコミット追加を監視し、push を検出するたびに呼び出し元スキルのレビューを自動実行する。駆動は loop スキルの dynamic モード + ScheduleWakeup の自己ペーシング。各 tick は ScheduleWakeup の `prompt` にユーザーが入力したスキル呼び出し（例: `/review-patch {PR} --watch [--fix] [--post]`）を verbatim で渡して再入する。tick 間で変わる状態は prompt に埋め込まず、すべて状態ファイルに置く。

セッション終了で watch も終了する。復旧は再度 watch を起動する。

## 呼び出し元ごとの対応

| 呼び出し元 | レビュー本体 | watch 中に置き換える事前確認 |
|---|---|---|
| review-patch | Step 0〜Phase 3 + 出力・投稿 | output-and-actions.md の投稿・修正の確認フロー |
| review-patch-crosscheck | 手順1〜5 | 手順4の「修正しますか？」と投稿前の事前確認 |

## 発火後アクション

watch 中は上表の事前確認を行わず、起動時のフラグ指定を事前確認済みとみなして次の動作に置き換える。

| フラグ | 発火ごとの動作 |
|---|---|
| なし | レビュー結果を会話へ提示して監視継続 |
| `--post` | 検証を通った指摘を GitHub へ投稿する（自分の PR でも可） |
| `--fix` | 自分の PR に限り、critical / should を修正し commit + push まで行う |

併用時は `--fix` を先に実行し、修正で解消した指摘を投稿から除外する。

## 状態ファイル

`{scratchpad}/review-watch-{スキル名}-{PR番号}.json`

```json
{"reviewedSha": "", "candidateSha": "", "runCount": 0}
```

会話コンテキストは summarize で失われうるため、tick 冒頭で必ずこのファイルから状態を復元する。初回か継続かの判別もファイルの有無で行う。

## 初回起動（状態ファイルなし）

1. `gh pr view {PR} --json author,headRefOid,state` を取得し、`--fix` 指定で author が自分以外なら拒否する
2. 現在の head SHA に対して「レビュー発火」をその場で実行する（初回は ScheduleWakeup を呼ばない）
3. Skill ツールで loop スキルを間隔指定なしで起動する。args はユーザーが入力したスキル呼び出しそのまま。以降の各発火が継続 tick になる

## 継続 tick

1. 状態ファイルを復元する
2. `gh pr view {PR} --json headRefOid,state` を取得する。失敗したらエラーを報告し `ScheduleWakeup(noop: true, delay: 60s)` で再試行する（ループは止めない）
3. state が MERGED / CLOSED → 実行回数と最終 `reviewedSha` を含めて完了報告し、`ScheduleWakeup(stop: true)` で終了する
4. head SHA が `reviewedSha` と同じ → `ScheduleWakeup(noop: true, delay: 60s)`
5. head SHA が `reviewedSha` とも `candidateSha` とも異なる → `candidateSha` に記録し、`ScheduleWakeup(noop: true, delay: 60s)`（連続 push のバーストでレビューを無駄打ちしないための安定確認）
6. head SHA が `candidateSha` と同じ（2 tick 連続で同一 ≒ 約1分安定）→ レビューを発火する

`ScheduleWakeup` の `reason` には「PR {n} の push 監視」等の具体的な文言を書く。

## レビュー発火

呼び出し元スキルのレビュー本体（上表）を、PR 指定時の worktree 作成からクリーンアップまでフル実行する。

- 差分は毎回 full PR diff。増分だけでは新コミットが既存コードと組み合わさって生む問題を見逃す
- 過去の発火分との重複指摘は、pr-review-setup.md の既存レビュー取得と会話コンテキストで除外する
- 完了後、`reviewedSha` を head SHA に更新し `runCount` を加算して状態ファイルへ書く。継続 tick では続けて `ScheduleWakeup(noop: false, delay: 60s)`
