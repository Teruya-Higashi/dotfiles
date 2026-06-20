---
name: worktree
description: git worktree を作成して独立した作業環境でタスクを実行し、完了後に削除する
---

## 概要

指定された作業を独立した git worktree 内で実行する。
作業完了後、worktree を削除してクリーンアップする。

メインの作業ツリーを汚さずに、別ブランチの作業や PR レビューを並行して行いたい場合に使う。

## 引数

$ARGUMENTS - 実行したい作業内容（例: "#1234 のバグを修正して"、"PR#4685 をレビューして"）

## 手順

### 1. メインリポジトリの状態確認

worktree 作成前にメインリポジトリがクリーンな状態か確認:

```bash
git status
```

意図しない差分がある場合は、先に対処する（stash または reset）。

### 2. 作業内容からブランチ名を決定

作業内容に応じてブランチ名を決定する:

- **PR レビューの場合**: `gh pr view {PR番号} --json headRefName -q .headRefName` でブランチ名を取得
- **Issue がある場合**: `{Issue 番号}-{短い説明}`（例: `1234-fix-timeout`）
- **その他の作業**: 作業内容を表す短い名前（例: `fix-typo-readme`, `investigate-error`）

プロジェクトにブランチ命名規約（`.claude/rules/` / `AGENTS.md` / `CONTRIBUTING.md` 等）がある場合はそれに従う。

**注意**: worktree は必ず新規ブランチまたは既存の作業ブランチで作成する。デフォルトブランチ（`main` / `master`）で直接作業しないこと。

### 3. worktree を作成

```bash
git fetch origin
```

**既存ブランチ（PR レビュー等）の場合:**
```bash
gh pr view {PR番号} --json headRefName -q .headRefName  # ブランチ名取得
# ローカルブランチが存在する場合はそのまま使用、なければ新規作成
if git show-ref --verify --quiet refs/heads/{branch}; then
  git worktree add worktrees/{name} {branch}
else
  git worktree add -b {branch} worktrees/{name} origin/{branch}
fi
```

**新規ブランチの場合:**
```bash
git worktree add worktrees/{name} -b {branch-name} origin/{default-branch}
```

`{default-branch}` はリポジトリのデフォルトブランチ（多くは `main`）。

### 4. 環境設定ファイルの trust（使用している場合のみ）

プロジェクトが mise / direnv などの環境管理ツールを使っている場合、worktree の設定ファイルを信頼する。

```bash
mise trust worktrees/{name}   # mise の場合
# direnv allow worktrees/{name}  # direnv の場合
```

使っていなければスキップする。

### 5. 絶対パスを記録

```bash
WORKTREE_PATH=$(cd worktrees/{name} && pwd)
echo "WORKTREE_PATH: $WORKTREE_PATH"
```

**重要**: 以降の全てのファイル操作で `$WORKTREE_PATH` を使用すること。Bash ツールは各呼び出しでシェル状態がリセットされるため、`cd` / `pushd` ではなく絶対パスを使う。

### 6. プロジェクトのアクティベート（使用している場合のみ）

コードインデックス系の MCP（Serena 等）を使っている場合、worktree の絶対パスで `activate_project` を呼び出す。

```
mcp__serena__activate_project:
  project: "$WORKTREE_PATH"
```

使っていなければスキップする。

### 7. 作業を実行

$ARGUMENTS で指定された作業を実行する。

**注意**: ファイル編集時は必ず `$WORKTREE_PATH` を含む絶対パスを使用すること。

### 7.5. レビュー投稿前の確認（PR レビューの場合）

PR レビューで、GitHub へコメントや approve を投稿する前に確認:

「以下の内容でレビューを投稿してよいですか？ (y/n)」
- レビュー結果のサマリーを提示
- approve / request changes / comment のどれかを明示
- y → 投稿して次へ
- n → 修正を継続

### 8. 作業完了の確認

作業が完了したら確認:

「作業は完了しましたか？ (y/n)」
- y → 手順 9 へ
- n → 作業を継続

### 9. push / PR 作成（必要な場合）

開発作業でコミットがある場合は PR を作成する。プロジェクトの PR 運用規約があればそれに従う。

**重要**: PR は原則 `--draft` で作成する。Ready for review にするかはユーザーが判断する。

### 10. worktree を削除

作業が完全に終了したら（PR マージ後、レビュー完了後など）:

```bash
git worktree remove worktrees/{name}
# submodule を含むリポジトリでは削除が拒否されることがある。その場合は --force:
# git worktree remove --force worktrees/{name}
```

手順 6 でプロジェクトをアクティベートした場合は、元のパスで `activate_project` を再実行する。

## 例

```bash
# Issue の作業
/worktree #1234 のバグを修正して

# PR レビュー
/worktree PR#4685 をレビューして、問題があればコメントを残して

# 一時的な調査
/worktree このエラーの原因を調査して
```

## 注意事項

- **全てのファイル操作で worktree の絶対パス（`$WORKTREE_PATH`）を使用すること**
  - メインリポジトリのパスを使うと、メインのブランチに意図しない差分が生じる
- 作業中に commit する場合は、適切なブランチ名で作業すること
- 同じファイルを複数 worktree で同時に編集しないこと
- worktree 内での変更は、メインディレクトリには影響しない
