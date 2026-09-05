# local-review helper

review-patch / review-patch-crosscheck（producer）と reply-pr-review（consumer）が別セッションから同じ review directory の event を読み書きするときに、解釈がぶれると壊れる状態操作をスクリプト化したbash CLI。判断規則はスキル文書に残す。

- 呼び出し: グローバルfile taskの`local-review:event`、`local-review:reduce`、`local-review:test`を使う
- 出力: stdout に JSON 1 行。成功は `ok: true`
- 依存: mise、bash 3.2 以上と PATH 上の jq
- 制約: ファイルを削除しない（`ln` / `mv -f` だけ）。temporary file は review directory の `tmp/` にだけ作る

## 別repository・別端末からの呼び出し

実体はdotfilesの`.config/mise/tasks/local-review/`に置く。`scripts/link.sh`が`~/.config/mise/tasks/local-review`へリンクするため、各端末で通常のdotfilesセットアップを行えばclone先によらず利用できる。既存端末ではdotfiles rootで次のリンク設定だけを実行してもよい。

```bash
mkdir -p ~/.config/mise/tasks
ln -sfn "$(pwd)/.config/mise/tasks/local-review" ~/.config/mise/tasks/local-review
```

別repositoryからそのまま実行できる。

```bash
mise run --quiet --raw local-review:event -- put --review-dir "$review_directory" --file "$payload"
mise run --quiet --raw local-review:reduce -- --review-dir "$review_directory"
```

`review_directory`と`payload`は呼び出し元repositoryで絶対pathへ解決しておく。`--quiet --raw`でstdoutのJSONをprefixなしで受け取り、stderrは分離する。開始時に`mise tasks info local-review:event --json`と`mise tasks info local-review:reduce --json`の`file`の実pathがこのdotfilesのscriptを指すことを確認する。作業先に同名taskがあり上書きされる場合は、`mise run --quiet --raw "${XDG_CONFIG_HOME:-$HOME/.config}/mise/tasks/local-review/event" -- put ...`（reduceも同様）のfile task指定でグローバル側を選ぶ。`//:`は作業先repositoryの指定になるため使わない。

miseの[file tasks](https://mise.jdx.dev/tasks/file-tasks.html)と[task configuration](https://mise.jdx.dev/tasks/task-configuration.html)を参照。

## review directory

```text
{git common dir の親}/tmp/local-review/{review-id}/
├── manifest.json     # producer だけが書く（helper は読まない）
├── events/*.json     # 正本 event。ファイル名は event ID
└── tmp/
```

## サブコマンド

| コマンド | 契約 |
|---|---|
| `event put --review-dir DIR --file F` | schema・ID・path・line を検証して `events/{id}.json` を `ln` で no-replace に作る。同一 ID・同一内容は `reused: true`、内容違いは exit 4。同時書き込みでも片方だけが勝つ |
| `reduce --review-dir DIR` | 最新runの主要fieldと`review_run`完全object、thread状態、`inconsistencies`、`invalid`を返す。invalidが1件でもあれば`ok:false`、空threadsでfail closedする |

read-only の sandbox では `reduce` だけ通り、`put` は exit 8。

## event

ID は field から導ける形に固定する。同じ内容を別セッションが書いても同じファイル名になり、冪等になる。

| type | id | 必須 field | 意味 |
|---|---|---|---|
| finding | `finding-{finding_id}-{run_seq}` | finding_id, run_seq, path, body（line は任意） | 指摘。内容が変わったときは新しい run_seq で書き直す。解消後の再発は新しい finding として扱う |
| review-run | `review-run-{run_seq 6 桁}` | run_seq, review_id, producer, repository_common_dir, worktree_root, branch, target, diff_mode, diff_fingerprint, base_sha, head_sha, fixed diff_args, findings, actions（bodyは任意） | identityを含むrunの確定snapshot。producer actionはここに載ったものだけ有効 |
| reply | `reply-{SHA-256(reply_to)先頭24文字}` | reply_to（finding または reviewer-reply）, body | consumerの返信。put成功時点で有効 |
| reviewer-reply | `reviewer-reply-{SHA-256(reply_to NUL body)先頭24文字}` | reply_to（reply）, body | producerの追加返信。本文変更時は別IDとなり、review-runのactionsで公開する |
| resolved | `resolved-{SHA-256(reply_to)先頭24文字}` | reply_to（thread末尾のfinding / reply / reviewer-reply） | review-runのactionsで公開する解消 |

共通fieldは`id`、`type`、`created_at`。run_seqは1..999999。正本filenameは必ず`{id}.json`。`path`は絶対pathと`.` / `..` segmentを拒否する。review-runの`diff_args`は`diff_mode`ごとの安全な固定形とbase/head SHAに完全一致する場合だけ受理する。producerはfindingとactionをputした後、review-runを最後にputする。未公開actionはreduceに影響しない。公開actionの親欠損、公開findingまで遡れないreply/action、同じ親への複数message、最新run内の同一finding_id複数versionはinconsistencyになる。

## exit code

| code | 意味 |
|---|---|
| 0 | 成功 |
| 1 | 内部エラー・I/O 失敗 |
| 2 | 引数不正 |
| 4 | collision（同一 ID の内容違い） |
| 5 | 検証失敗 |
| 8 | review directory へ書けない |

## テスト

`mise run --quiet --raw local-review:test`。`${TMPDIR:-/tmp}/codex-local-review-test/run.XXXXXX/`にfixtureを作り、削除しない。
