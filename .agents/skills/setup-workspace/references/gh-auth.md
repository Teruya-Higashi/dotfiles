# gh 認証の復旧

目的の `gh` コマンドが token invalid / `401` などの認証エラーになり、macOS Keychain を参照できない環境の場合に限り、Git credential helper が有効な GitHub credential を返すときだけ次を使う。事前確認として `gh auth status` は実行しない。token は標準出力・ファイル・親シェルへ残さず、対象の `gh` プロセスにだけ渡す。

```sh
(
  set +x
  unset GH_TOKEN GITHUB_TOKEN
  token=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill | sed -n 's/^password=//p')

  if [ -z "$token" ]; then
    printf '%s\n' 'GitHub credential not found' >&2
    exit 1
  fi

  GH_TOKEN="$token" command gh pr view 1234
)
```

- 最終行の `gh pr view 1234` を実行したい `gh` コマンドへ置き換える。
- `gh auth setup-git` は Git が `gh` の credential を使うための設定であり、この用途には使わない。
- `echo "$token"`、`gh auth token`、`gh auth status --show-token`、`export GH_TOKEN=...`、`gh auth login --insecure-storage` は使わない。
