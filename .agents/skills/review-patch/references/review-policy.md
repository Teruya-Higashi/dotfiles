# レビュー方針

## 4タグ体系

上から順に判定し、最初に該当したタグを使う。

| # | タグ | GitHub画像バッジ | 判定基準 |
|---:|---|---|---|
| 1 | `critical` | `![critical](https://img.shields.io/badge/review-critical-red.svg)` | 特定条件を含め、クラッシュ、データ破損、セキュリティ侵害、主要機能の誤動作が起きる |
| 2 | `should` | `![should](https://img.shields.io/badge/review-should-orange.svg)` | 動作はするが、エラー処理、設計、保守性、性能、テスト品質に実質的な問題がある |
| 3 | `nits` | `![nits](https://img.shields.io/badge/review-nits-blue.svg)` | 命名や文書の正確性など、任意修正の軽微な問題 |
| 4 | `ask` | `![ask](https://img.shields.io/badge/review-ask-purple.svg)` | 正しさが仕様・意図に依存し、作者への確認が必要 |

`must` / `bug`など別体系の入力は機械変換せず、この基準で判定し直す。

## レビュー対象外

自動生成・ベンダリングされたファイルにはインライン指摘を付けない。

- lockファイル（`package-lock.json`、`pnpm-lock.yaml`、`go.sum`、`Cargo.lock`、`poetry.lock`等）
- コード生成ツールの出力（GraphQL codegen、protobuf、ORM生成コード、`*_mock.go`等）
- `vendor/`、`node_modules/`等のベンダリングされた依存
- リポジトリが`.gitattributes`等で生成物として明示したファイル

生成元の変更に問題がある場合は、生成物ではなく生成元を指摘する。

## ルール参照

- 規約を読めば判断できる事項を`ask`にしない
- 明確なルール違反は指摘対象とするが、タグはルールの文言ではなく実害で決める
- 汎用ベストプラクティスだけを根拠に`should`以上へ上げない
