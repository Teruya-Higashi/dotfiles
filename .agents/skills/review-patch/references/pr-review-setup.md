# PRレビューのセットアップ

PR番号・URL指定時は`gh-ops`に従い、GitHub上の正確なhead SHAを専用worktreeへ隔離する。本体checkoutをstash、reset、checkout、switchしない。

## 1. PR情報

対象リポジトリを明示して、少なくとも次を取得する。

```bash
gh pr view "$pr_number" --repo "$base_repo" \
  --json number,author,headRefName,headRefOid,baseRefName,title,body,url,additions,deletions,changedFiles,closingIssuesReferences,commits
```

`base_repo`、対応するローカルremote、`baseRefName`、`headRefOid`を確定する。

## 2. 正確なheadの隔離

1. base refを対応remoteから一意な一時refへfetchし、その完全なcommit SHAを`base_sha`として固定する。remote-tracking refや`FETCH_HEAD`を後から暗黙参照しない。
2. `refs/pull/{PR}/head`を一意な一時refへfetchする。既存local branchや`origin/{head}`を再利用しない。
3. fetchしたcommitが`headRefOid`と一致することを確認する。
4. `mktemp -d`で親ディレクトリを作り、そのSHAをdetached HEADの専用worktreeへ展開する。
5. `rev-parse HEAD`、`rev-parse --show-toplevel`、`worktree list --porcelain`でSHAと隔離を検証する。

fork PRでもbase repositoryのpull refを使う。本体checkoutへフォールバックしない。

## 3. 差分

固定した`base_sha`と`head_sha`のmerge-baseを計算し、完全なcommit SHAであることを確認する。専用worktreeで次を取得する。

```bash
git -C "$worktree_path" diff "$merge_base_sha...$head_sha" --stat
git -C "$worktree_path" diff "$merge_base_sha...$head_sha"
```

## 4. 要件

Phase 1で、PR本文と`closingIssuesReferences`から要件・判断を記録したlinked issueを特定し、各issueの本文と全コメントをページネーション付きで読む。これは仕様理解の入力であり、他レビュアーの指摘ではない。

## 5. 既存レビューとの重複排除

Validationで独立したレビュー候補を得た後、次の全種別をページネーション付きで取得する。

- インラインコメントと返信: `pulls/{PR}/comments`
- レビュー本文: `pulls/{PR}/reviews`
- PR会話コメント: `issues/{PR}/comments`

文字列一致ではなく、観点、根拠、発火条件、修正方針で論点を照合する。

- 作者が回答・修正済みの論点は再指摘しない
- botや人が未解決で指摘済みの同一論点も重複投稿しない
- 既存レビューで全候補が網羅されていれば、追加指摘なしと報告して投稿を省く

既存レビューを先に読んでレビュー候補を誘導しない。Validation後の重複排除にだけ使う。
