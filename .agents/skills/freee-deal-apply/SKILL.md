---
name: freee-deal-apply
description: deal-plan.md のドラフトに基づき freee 会計の取引(deals)を作成し、証憑を紐付ける。新規取引は POST /api/1/deals、既存取引への証憑紐付けは GET で検索後 PUT /api/1/deals/{id} で実行する。
---

# freee 取引(deals)作成スキル

## 概要

`freee-deal-plan` スキルが出力した `deal-plan.md` を入力として、ドラフトに基づき freee 会計の取引(deals)を作成し、証憑(receipts)を紐付ける。

### スキル間の関係

| スキル | フェーズ | API操作 | 出力 |
|--------|---------|---------|------|
| `freee-deal-plan` | 1. ドラフト作成 | GET のみ | `deal-plan.md`（ドラフト） |
| **`freee-deal-apply`** | **2. 取引登録・証憑紐付け** | **GET / POST / PUT** | **`deal-plan.md`（チェック済み更新）** |

## 入力

- `deal_plan_file`: deal-plan.md のパス（デフォルト: `deal-plan.md`）

deal-plan.md のメタ情報から以下を読み取る:
- `事業所ID`: company_id
- `対象件数`: 全行数（検証用）

## 前提条件

- `deal-plan.md` が `freee-deal-plan` スキルの仕様に準拠していること
- freee MCP サーバーが接続済みであること
- 対象事業所の OAuth 認証が有効であること

## 実施手順

### Phase 1: 認証・事業所確認 + deal-plan.md パース

1. `freee_auth_status` と `freee_get_current_company` で認証・事業所を確認する。
   - 認証無効時は `freee-api-skill` のエラー対応手順に従う。
   - `freee_get_current_company` の company_id と deal-plan.md の事業所ID が一致することを検証する。

2. deal-plan.md を読み取り、推定一覧テーブルを全行パースする。

3. 各行を以下のパターンに分類する:

| パターン | 取引登録済み | 証憑紐付け済み | アクション |
|----------|:---:|:---:|---|
| A: 新規登録 | `[ ]` | `[ ]` | POST /api/1/deals（receipt_ids 付き） |
| B: 紐付けのみ | `[x]` | `[ ]` | GET で既存取引検索 → PUT で receipt_ids 追加 |
| C: 完了済み | `[x]` | `[x]` | スキップ |
| D: スキップ対象 | `[ ]` | `[ ]` | 確度=低 かつ ドラフト全値 null → スキップ |

4. 補足セクション「同日・同取引先の証憑グルーピング」を読み取り、グルーピング情報を構築する。

### Phase 2: ユーザー確認ゲート

5. **AskUserQuestion** で以下をユーザーに提示し、承認を得る。承認なしで Phase 3 以降に進むことは禁止。
   - パターン別の件数内訳（A: 新規登録 N件 / B: 紐付けのみ N件 / C: 完了済み N件 / D: スキップ N件）
   - パターン B の取引先一覧（紐付け対象の既存取引を検索する必要があるため）
   - グルーピング対象の有無と件数
   - 「処理を開始してよいか？」

### Phase 3: 逐次実行

deal-plan.md のテーブル順に1件ずつ処理する。各処理後に即座に deal-plan.md のチェックボックスを更新する。

#### パターン A: 新規取引登録（POST）

6. `推測される新規取引(ドラフト)` カラムから API パラメータを抽出する（後述「ドラフトカラムのパース仕様」参照）。

7. `POST /api/1/deals` を実行する。

リクエストボディ構築ルール:

```
{
  "company_id": <deal-plan.md の事業所ID>,
  "issue_date": <ドラフトの issue_date>,
  "type": <ドラフトの type>,
  "partner_id": <ドラフトの partner_id>,
  "receipt_ids": [<当該行の receipt_id>],
  "details": [
    {
      "account_item_id": <ドラフトの account_item_id>,
      "tax_code": <ドラフトの tax_code>,
      "amount": <ドラフトの amount>,
      "tag_ids": <ドラフトの tag_ids（空配列 [] の場合は省略）>,
      "item_id": <ドラフトの item_id（null の場合は省略）>,
      "description": <証憑内容から適切な備考を設定>
    }
  ],
  "payments": [
    {
      "amount": <ドラフトの amount>,
      "from_walletable_type": <payment の型部分>,
      "from_walletable_id": <payment の ID 部分>,
      "date": <ドラフトの issue_date>
    }
  ]
}
```

8. レスポンスの `deal.id` を確認し、成功なら deal-plan.md の当該行を `[x] | [x]` に更新する。

#### パターン A（グルーピングあり）: 複数証憑を1取引に紐付け

9. 補足セクションのグルーピング情報に該当する場合、グループ内の**最初の証憑**処理時に POST を実行する。

- `receipt_ids` にグループ内の**全 receipt_id** を含める。
- `details` にグループ内の各証憑を明細行として追加する（複数明細行）。
- `payments.amount` は合計金額とする。

10. グループ内の**2件目以降**の証憑は、POST 済みの取引に既に紐付いているため、deal-plan.md の更新のみ行う（API 呼び出し不要）。

#### パターン B: 既存取引への証憑紐付け（GET → PUT）

11. 既存取引を検索する。`GET /api/1/deals` に以下のパラメータを指定する:

```
{
  "company_id": <事業所ID>,
  "partner_id": <ドラフトの partner_id>,
  "type": <ドラフトの type>,
  "start_issue_date": <ドラフトの issue_date の月初 - 1ヶ月>,
  "end_issue_date": <ドラフトの issue_date の月末 + 1ヶ月>,
  "limit": 100
}
```

12. **金額マッチング**で対象取引を特定する。

- 重要: `issue_date`（発生日）は証憑の日付と一致しないことが多い（銀行引落日やカード決済日になるため）。`amount` での照合を優先する。
- GET 結果から `amount` がドラフトの `amount` と一致する取引を探す。
- 一致する取引が複数ある場合は、日付が最も近いものを選択する。

13. **日付範囲拡大**: 12 で見つからない場合、日付範囲を段階的に拡大する。

- 第1回: ±1ヶ月 → ±2ヶ月
- 第2回: ±2ヶ月 → ±3ヶ月
- 第3回: ±3ヶ月 → ±6ヶ月
- 全て失敗: エラーとして記録し、次の証憑に進む。

14. **グルーピング対応（パターン B）**: 同日・同取引先で複数証憑がグルーピングされている場合（例: ギークス SecurifyScan + ABEMA）、既存取引は合算金額（例: 1,136,300円）で登録されている。この場合:

- 合算金額で取引を検索する。
- 1つの取引に対して、グループ内の全 receipt_id をまとめて PUT する。

15. 対象取引が見つかったら、`PUT /api/1/deals/{id}` で証憑を紐付ける。

PUT リクエストボディ構築ルール:

```
{
  "company_id": <事業所ID>,
  "issue_date": <既存取引の issue_date（変更しない）>,
  "type": <既存取引の type（変更しない）>,
  "partner_id": <既存取引の partner_id（変更しない）>,
  "receipt_ids": [
    <既存取引に紐付き済みの receipt_id（あれば）>,
    <新たに紐付ける receipt_id>
  ],
  "details": [
    {
      "id": <既存明細行の id（必須: 省略すると削除される）>,
      "account_item_id": <既存値を保持>,
      "tax_code": <既存値を保持>,
      "amount": <既存値を保持>,
      "item_id": <既存値を保持（あれば）>,
      "tag_ids": <既存値を保持（あれば）>,
      "description": <既存値を保持（あれば）>
    }
  ]
}
```

**PUT 時の重要注意点:**

- `details[].id` を必ず指定すること。省略すると既存明細行が削除され、新規行として再作成される。
- `details` に含まれない既存の明細行は削除される。既存の全明細行を含める必要がある。
- `receipt_ids` は既存の紐付き済み receipt_id も含めた完全なリストを指定する。既存分を省略すると紐付けが解除される。
- 既存取引の値を変更する必要はない。証憑紐付けのみが目的。

16. PUT 成功後、deal-plan.md の当該行の `証憑紐付け済み` を `[x]` に更新する（`取引登録済み` は元々 `[x]`）。

#### パターン D: スキップ

17. 確度が `低` かつドラフトの全値が null の行はスキップする。deal-plan.md は更新しない（`[ ] | [ ]` のまま）。

### Phase 4: 完了レポート

18. 全件処理後、以下のサマリーをユーザーに提示する:
    - 新規登録成功: N件
    - 紐付け成功: N件
    - スキップ: N件
    - エラー: N件（エラー内容の一覧）

## ドラフトカラムのパース仕様

`推測される新規取引(ドラフト)` カラムは `<br>` 区切りの `key=value` 形式。

### パースルール

1. `<br>` で分割して各行を取得する。
2. 各行を `=` で key と value に分割する（最初の `=` で分割。value に `=` を含む可能性あり）。
3. value の型変換:

| key | 型 | 変換ルール | 例 |
|-----|-----|-----------|-----|
| `type` | string | そのまま | `expense`, `income` |
| `partner_id` | integer | 数値変換。`要新規作成` の場合はエラー（手動対応必要） | `110555417` |
| `account_item_id` | integer | 数値変換 | `485243160` |
| `tax_code` | integer | 数値変換 | `136` |
| `tag_ids` | array[integer] | `[]` → 空配列、`[N]` → [N]、`[N, M]` → [N, M] | `[14887258, 14888652]` |
| `item_id` | integer \| null | `null` → 省略、数値 → 数値変換 | `189325183` |
| `payment` | string | `{type}:{id}` 形式。`:` で分割 | `private_account_item:485243111` |
| `issue_date` | string | そのまま（yyyy-mm-dd） | `2025-11-05` |
| `amount` | integer | 数値変換 | `2970` |

### payment フィールドの分解

`payment` は `{from_walletable_type}:{from_walletable_id}` 形式。

| payment 値の例 | from_walletable_type | from_walletable_id |
|---|---|---|
| `private_account_item:485243111` | `private_account_item` | `485243111` |
| `bank_account:2316581` | `bank_account` | `2316581` |
| `credit_card:12345` | `credit_card` | `12345` |
| `wallet:1` | `wallet` | `1` |

## deal-plan.md 更新仕様

### チェックボックス更新

各行の末尾にある `取引登録済み` と `証憑紐付け済み` カラムを更新する。

| 操作 | 更新前 | 更新後 |
|------|--------|--------|
| パターン A（新規登録）成功 | `\| [ ] \| [ ] \|` | `\| [x] \| [x] \|` |
| パターン B（紐付け）成功 | `\| [x] \| [ ] \|` | `\| [x] \| [x] \|` |
| エラー | 変更なし | 変更なし |

### 更新方法

- Edit ツールで該当行の `| [ ] | [ ] |` → `| [x] | [x] |` に置換する。
- 1件処理するごとに即座に更新する（バッチではなく逐次更新）。
- これにより、処理中断後の再実行時に完了済み行をスキップできる（冪等性）。

### エラー時の記録

API エラーが発生した場合、deal-plan.md は更新せず（チェックボックスはそのまま）、メインエージェントのコンテキスト内でエラー情報を保持する。Phase 4 の完了レポートでまとめてユーザーに報告する。

## 冪等性（再実行安全性）

- `[x] | [x]` の行は常にスキップされるため、同じ deal-plan.md に対して複数回実行しても安全。
- 中断後の再実行: 未完了行（`[ ]` が残る行）のみ処理される。
- POST の重複実行リスク: POST 後に deal-plan.md 更新前にクラッシュした場合、再実行で重複取引が作成される可能性がある。この場合はユーザーが freee Web UI で確認・削除する必要がある。

## エラーハンドリング

### API エラー

| エラー | 対応 |
|--------|------|
| 401 Unauthorized | 認証切れ。処理を中断し、ユーザーに再認証を促す |
| 404 Not Found（PUT 時） | 取引IDが無効。エラー記録して次へ |
| 422 Unprocessable Entity | パラメータ不正。エラー内容を記録して次へ |
| 429 Too Many Requests | レートリミット。60秒待機後にリトライ（最大3回） |
| 500 以上 | サーバーエラー。30秒待機後にリトライ（最大2回） |

### 取引検索失敗（パターン B）

既存取引が見つからない場合:
1. 日付範囲を段階的に拡大して再検索する（Phase 3 ステップ 13 参照）。
2. 全範囲で見つからない場合、エラーとして記録し、次の証憑に進む。
3. 完了レポートで未紐付け一覧をユーザーに報告する。

### partner_id=要新規作成

取引先が未登録の場合（`partner_id=要新規作成`）:
- 当該行をスキップし、エラー記録する。
- 完了レポートで取引先の新規作成が必要な旨をユーザーに報告する。
- 取引先作成（`POST /api/1/partners`）はこのスキルのスコープ外とする。

## 安全策

### 実行しない操作

- `DELETE /api/1/deals/{id}` - 取引の削除は行わない。
- `DELETE /api/1/receipts/{id}` - 証憑の削除は行わない。
- 既存取引の金額・勘定科目・取引先などの変更（PUT 時は receipt_ids の追加のみ）。

### ユーザー確認

- Phase 2 で処理開始前に必ずユーザー承認を得る。
- 処理中の個別確認は行わない（1件ずつ確認すると大量件数で非実用的なため）。

## 依存スキル

- `freee-api-skill`: MCP ツール（`freee_auth_status`, `freee_get_current_company`, `freee_api_get`, `freee_api_post`, `freee_api_put`）を使用。
- `freee-deal-plan`: 入力ファイル（deal-plan.md）の生成元。deal-plan.md の仕様は当該スキルの SKILL.md を参照。
