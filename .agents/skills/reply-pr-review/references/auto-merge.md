# 返信後の自動マージ

`--auto-merge --rounds N --fix`を明示した GitHub source だけに適用する。`--local`は禁止。watch の終了条件を満たした後に読み、処理中 pending / resolvePending があれば先に完了する。通常の返信・watch は Ready 化も merge 要求も行わない。

## 直前の検証

1. [GitHub 共通規約](../../_shared/github-writing.md) に従い対象 base repo、PR、認証ユーザーを固定する。3 種類のコメント API を全件再取得し、未返信 0 件、unconfirmedIds 空、未完了バッチ・resolve なしを確認する。
2. PR の state、author、head/base repository、headRefOid、baseRefName、isDraft と REST resource の stack を取得する。自分の同一 repository PR だけを扱う。MERGED なら再取得した状態を報告して終了、CLOSED なら要求しない。
3. 初回のマージ移行時だけ、終了の根拠となる lastCompletedSnapshot または convergedSnapshot と取得した repo・PR 番号・head・base を照合する。一致した値と stack number（通常 PR は null）を `mergeSnapshot`へ固定し、head_sha を `mergeHeadSha`にも保存する。再検証・再開では保存値と比較するだけで上書きしない。snapshot 欠損は停止する。`stack: null`は通常 PR。stack がある場合は `base.ref == stack.base.ref`の最下層の未マージ PR だけを許す。stack field が取得不能・不明なら通常 PR と推測しない。上層 PR は Ready 化前に停止する。
4. Ready 化直前と merge 要求直前に、未返信・未確認がないこと、OPEN、author/repo、mergeSnapshot と同じ head/base/stack number、最下層条件を再確認する。更新があれば要求せず理由を報告する。Draft の場合だけ `gh pr ready`を実行して再取得する。

## 通常 PR

CLI の `gh pr merge --help`でフラグを確認し、対象 repo と固定した SHA を渡す。

```bash
gh pr merge "{PR}" --repo "{base_repo}" --squash --auto --match-head-commit "{mergeHeadSha}"
```

実行後は `gh pr view`で state と autoMergeRequest を再取得する。MERGED はマージ完了、予約だけなら「自動マージ予約済み」と報告する。merge queue を使う repo ではキュー状態も照合し、予約・キュー投入をマージ済みと報告しない。確認不能、予約なし、head 不一致は成功扱いしない。

## Stacked PR

[GitHub の stack API 説明](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests-apis-and-webhooks) に従い非同期 merge を使う。指定 PR より下の open PR も含む操作のため、上記の最下層条件を毎回維持する。

初回にだけ `phase: merging`、固定した mergeSnapshot、mergeHeadSha、mergeRequestUuid（初期 null）、mergeRequestSent（初期 false）を保存する。再入時は保存値を初期化せず照合し、通常レビューの取得へ戻らない。

1. `gh pr checks {PR} --repo {base_repo} --required --json bucket,name`で必須チェックを取得する。pending（CLI exit 8）なら 60 秒以内の次 tick、fail/cancel なら要求せず終了する。全件 pass/skipping なら進む。空なら必須チェック未設定であることを確認し、取得失敗・不明と区別する。
2. 直前の検証をやり直し、保存した head/base と最下層条件が変わっていないことを確認する。既存 UUID があれば新しい要求を送らず手順4へ進む。
3. private JSON payload に `sha: mergeHeadSha`、`merge_method: squash`、`merge_action: default`、`bypass_rules: false`を生成する。送信前に mergeRequestSent:true を atomic に保存し、次の要求を 1 回だけ送る。

```bash
gh api --method PUT "repos/{base_repo}/pulls/{PR}/merge-async" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  --include --input "{payload_file}"
```

HTTP status と本文を別々に保存する。409 は CLI が非ゼロでも本文を確認し、既存要求の UUID を取得する。`details.expected_head_sha`、merge options、bypass が今回の head・意図と一致することを確認してから mergeRequestUuid を保存する。不一致・UUID 不明なら停止する。送信後の応答が不明、または送信済みで UUID がない状態から再開した場合は、再送せず PR 状態を確認して不明な結果を報告する。

4. 保存済み UUID で `GET repos/{base_repo}/pulls/{PR}/merge-async/{mergeRequestUuid}`を照会する。pending では expected_head_sha と options を照合して次 tick、failed なら details.message を報告して終了する。transport error は UUID を保持し、照会だけを再試行する。

| 応答 | 扱い |
|---|---|
| 202 | 受理 UUID を保存し、その要求を照会 |
| 200 | merged / enqueued を本文と PR 再取得で確認 |
| 409 | 同じ条件の既存 UUID を保存して照会。重複要求しない |
| 400 / 403 / 422 | 理由を報告して終了。保護規則を迂回しない |
| merged | PR が MERGED であることを再取得して完了を報告 |
| enqueued | キュー投入済みと報告。マージ済みではない |
| 404 | PR 状態を確認し、OPEN なら再要求せず状態不明を報告 |

enqueued は非同期要求としての終端で、後のマージで変化しない。以後の結果が必要なら PR 状態を取得する。要求の結果は最終更新から 24 時間で期限切れになるため、404 を新規要求の根拠にしない。

終了時は取得した状態・回数・最終結果を報告し、全 field を保持して phase だけを stopped にする。未確認 ID、送信済みフラグ、UUID、固定 snapshot は停止・再起動でも消去しない。`--admin`、bypass_rules:true、強制的な承認・チェック省略、下層 PR の一括処理を追加しない。

仕様確認先: [非同期マージと結果取得](https://docs.github.com/en/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request-asynchronously)、[PR checks](https://cli.github.com/manual/gh_pr_checks)、[PR merge](https://cli.github.com/manual/gh_pr_merge)。
