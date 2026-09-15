---
name: worktree
description: Use when 独立した git worktree で別ブランチの作業、並行タスク、PR の検証・レビューを実行するとき。
---

## 概要

Claude / Codex のどちらでも、git worktree の準備、作業コンテキストの引き渡し、終了後のクリーンアップを行う。引数は実行したい作業内容（例: 「#1234 のバグを修正して」「PR#4685 をレビューして」）。

既存のネイティブ worktree がある場合も Git の登録情報で確認する。リポジトリが作成手段を指定していれば従う。ツールが自動作成したことだけでローカル設定の引き継ぎや環境準備が済んだとはみなさない。

## 1. 状態と作業場所の確認

`git status --short`、`git worktree list --porcelain`、`git rev-parse --show-toplevel`、`git rev-parse --path-format=absolute --git-common-dir` で現在の checkout、本体、既存 worktree を確認する。

- 本体の未コミット変更は残したまま別 worktree を作る。作成のために stash / reset しない
- 既存 worktree は対象 branch / SHA が一致し、その作業に使える場合だけ再利用する。パスに `worktrees/` が含まれるだけでは判定しない
- 本体・作業先を canonical な絶対パスで記録し、今回自分が作成した worktree と再利用したものを区別する
- `AGENTS.md`、`CLAUDE.md`、ブランチ命名・配置規約を確認する。`gh` が必要なら `gh-ops` を読む

## 2. ブランチと worktree の作成

Issue があれば `{番号}-{短い説明}`、なければ作業を表す短い名前を使う。デフォルトブランチはリポジトリ情報から確定し、直接の開発作業には使わない。

```bash
# 各 placeholder は確認済みの値に置換し、shell-safe に quote する
git fetch "{remote}"
git worktree add -b "{branch}" "{absolute_worktree_path}" "{remote}/{default_branch}"
```

既存ブランチは最新の対象 commit を確認して使う。レビューのみで commit 予定がなければ `git worktree add --detach "{absolute_worktree_path}" "{head_sha}"` を使い、二重 checkout を避ける。

PR レビューは [`../review-patch/references/pr-review-setup.md`](../review-patch/references/pr-review-setup.md) の正確な head 隔離に従う。fork を含め pull ref と GitHub の head SHA を照合し、作成後は次の環境準備へ進む。

## 3. ローカル設定の引き継ぎ

本体の `.worktreeinclude` がある場合は、そこに指定された gitignore 済みファイルをコピーする。`git worktree add` はこの処理を自動では行わない。ネイティブ機構がコピー済みなら重ねて上書きしない。

1. 本体で `git ls-files --others --ignored --exclude-standard -z` と `git ls-files --others --ignored --exclude-from=.worktreeinclude -z` を取得し、NUL 区切りのまま共通するパスを選ぶ
2. 読み取り・書き込みが許可された通常ファイルだけを対象にする。symlink や本体外へ解決されるパスはコピーしない。アクセス拒否対象は読まず、必要な設定を引き継げなければ不足を報告する
3. コピー先が worktree 内であり、既存ファイルや symlink を上書きしないことを確認して、親ディレクトリを作り属性を保ってコピーする

設定の内容をログへ表示しない。`.worktreeinclude` がなければコピーを省略する。

## 4. 環境準備

- mise / direnv を使う場合は設定を確認し、コピー後に worktree の絶対パスに対して trust / allow を行う
- Serena 等を使う場合は利用可能な `activate_project` に worktree の絶対パスを渡す。同名登録の曖昧さを避けるためプロジェクト名は使わない
- 切り替えツールが使えなければ、本体へ向いたツールで編集せず、対象パスを明示できるファイル操作や検索を使う。ツール設定を自動変更しない

## 5. 後続スキルへの引き渡し

シェル呼び出し間の変数や cwd に依存せず、会話内で具体値を渡す。

```text
active_worktree_path: /absolute/path/to/worktrees/task-name
worktree_isolation_required: true
```

引き渡し前に、指定パスが `git worktree list --porcelain` に存在し、`git -C "{active_worktree_path}" rev-parse --show-toplevel` と一致し、本体と異なることを確認する。

後続スキル・サブエージェントには同じ具体値を渡し、ツールの `workdir`、ファイル操作、成果物の出力先に使う。相対パス、変数名、消失した cwd から本体へフォールバックしない。専用 PR worktree を新規作成した場合は新しい具体値へ更新する。レビュー結果を削除後も残す必要がある場合は、レビュースキルが定める worktree 外の成果物保存先を併せて渡す。

## 6. 作業と完了処理

指定された作業を実行し、対応する検証を行う。許可済みの作業について完了確認を繰り返さない。PR 作成を依頼された場合は `create-pr`、レビュー投稿は `review-patch` の手順を使い、既存の依頼・承認範囲を引き継ぐ。

終了時は次を確認する。

- 今回作成した worktree であり、未コミット変更・未保存成果物・未退避の commit がない
- レビュー結果など必要な成果物が削除後も参照できる場所に保存されている
- `--local` レビューの manifest が active の間は、返信対応に必要な worktree を維持する

Serena 等を切り替えた場合は削除前に元の絶対パスへ戻す。その後 `git worktree remove "{absolute_worktree_path}"` で削除する。再利用した worktree は削除しない。削除が拒否された場合は原因を確認し、未保存データを捨てる `--force` を自動実行しない。保持した worktree、commit、成果物のパスを最終報告に含める。
