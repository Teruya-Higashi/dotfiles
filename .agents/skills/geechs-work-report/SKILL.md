---
name: geechs-work-report
description: geechs 作業報告アプリで当月の作業報告を入力・保存する
---

# /geechs-work-report - 作業報告の入力

geechs 作業報告アプリ（https://geechs.my.site.com/s/）で当月の作業報告を入力・保存するスキル。
playwright-cli を使用してブラウザ操作を行う。

## 前提

- `playwright-cli` が利用可能であること

## 手順

### 1. Cookie の取得

ユーザーに Cookie を尋ねる。

```
作業報告アプリの Cookie を貼り付けてください。
ブラウザの DevTools > Application > Cookies からコピーできます。
```

### 2. ブラウザを開いて Cookie を設定

```bash
playwright-cli open https://geechs.my.site.com/s/
```

ユーザーから受け取った Cookie 文字列をパースし、各 Cookie を設定する。
Cookie はセミコロン区切りの `name=value` ペア。

```bash
# 各 Cookie を設定（domain は geechs.my.site.com）
playwright-cli cookie-set <name> '<value>' --domain=geechs.my.site.com
```

`__Secure-` プレフィックスの Cookie には `--secure` を付与する。

Cookie 設定後、ページを再読み込みする。

```bash
playwright-cli goto https://geechs.my.site.com/s/
```

ページタイトルが「Home - 作業報告アプリ」であることを確認する。ログインページにリダイレクトされた場合は Cookie が無効。

### 3. 作業報告一覧へ遷移

snapshot を取得し、メニューから「作業報告一覧」をクリックする。

```bash
playwright-cli snapshot
# snapshot から「作業報告一覧」menuitem の ref を特定
playwright-cli click <ref>
```

## プロジェクト A: SecurifyScanのバックエンド開発

### 4a. 当月の作業報告を開く

snapshot から「SecurifyScanのバックエンド開発」プロジェクトの当月（YYYY年MM月度）で「未提出」ステータスの行を探し、作業報告番号のリンクをクリックする。

```bash
# snapshot で該当行の link ref を特定
playwright-cli click <ref>
```

### 4a-check. 入力済みチェック

作業報告ページを開いた後、snapshot でテーブルの内容を確認する。
すでに作業内容が入力されている（平日の作業内容セルが空でない）場合は、ユーザーに以下を確認する:

```
SecurifyScanのバックエンド開発の当月作業報告はすでに入力済みです。スキップしますか？ (y/n)
```

- `y` の場合: プロジェクト B に進む
- `n` の場合: 上書きで入力を続行する

### 5a. アンケートモーダルを閉じる

ページ遷移後にアンケート回答モーダルが表示される場合がある。表示された場合は「あとで回答」ボタンをクリックして閉じる。

```bash
playwright-cli snapshot
# 「あとで回答」ボタンが存在すればクリック
playwright-cli click <ref>
```

### 6a. 標準時間を入力

1. 「編集」ボタン（標準時間セクション付近の最初のもの）をクリック
2. 以下の値を入力:
   - 標準開始時間: `10:00`
   - 標準終了時間: `19:00`
   - 標準休憩開始時間: `12:00`
   - 標準休憩終了時間: `13:00`
3. 「保存」ボタンをクリック

```bash
playwright-cli snapshot
# 編集ボタンをクリック
playwright-cli click <編集ボタンref>

# snapshot で各 textbox ref を特定
playwright-cli fill <標準開始時間ref> "10:00"
playwright-cli fill <標準終了時間ref> "19:00"
playwright-cli fill <標準休憩開始時間ref> "12:00"
playwright-cli fill <標準休憩終了時間ref> "13:00"

# 保存
playwright-cli click <保存ボタンref>
```

### 7a. 作業内容を入力

1. 「編集」ボタンをクリック
2. snapshot でテーブルの各行を確認し、作業時間が `8:00` 等（0:00 および空欄以外）の日付を特定
3. 該当日の「作業内容」textbox に `SecurifyScanバックエンド開発` を入力
4. 「保存」ボタンをクリック

```bash
playwright-cli snapshot
# 編集ボタンをクリック
playwright-cli click <編集ボタンref>

# snapshot を読み取り、作業時間が発生している行の作業内容 textbox ref を特定
# 各 row の構造: 日付 / 開始時刻 / 終了時刻 / 休憩時間 / 作業内容(textbox) / 作業時間 / 特記事項
# 作業時間セルが 0:00 でない、かつ空でない行が対象

playwright-cli fill <作業内容ref> "SecurifyScanバックエンド開発"
# ... 対象日すべてに対して実行

# 保存
playwright-cli click <保存ボタンref>
```

### 8a. 完了確認

保存後にスクリーンショットを撮影し、ユーザーに結果を表示する。

```bash
mkdir -p .playwright-cli/capture
playwright-cli screenshot --filename=.playwright-cli/capture/geechs-report-securify-saved.png
```

## プロジェクト B: ABEMAコンテンツ管理システム

### 4b. 作業報告一覧に戻る

作業報告一覧ページに戻る。

```bash
playwright-cli snapshot
# メニューから「作業報告一覧」をクリック
playwright-cli click <ref>
```

### 5b. 当月の作業報告を開く

snapshot から「ABEMAコンテンツ管理システム全般の設計・開発とそれに付随する業務」プロジェクトの当月（YYYY年MM月度）で「未提出」ステータスの行を探し、作業報告番号のリンクをクリックする。

```bash
# snapshot で該当行の link ref を特定
playwright-cli click <ref>
```

### 5b-check. 入力済みチェック

作業報告ページを開いた後、snapshot でテーブルの内容を確認する。
すでに作業内容が入力されている（平日の作業内容セルが空でない）場合は、ユーザーに以下を確認する:

```
ABEMAコンテンツ管理システムの当月作業報告はすでに入力済みです。スキップしますか？ (y/n)
```

- `y` の場合: 完了ステップに進む
- `n` の場合: 上書きで入力を続行する

### 6b. アンケートモーダルを閉じる

ページ遷移後にアンケート回答モーダルが表示される場合がある。表示された場合は「あとで回答」ボタンをクリックして閉じる。

```bash
playwright-cli snapshot
# 「あとで回答」ボタンが存在すればクリック
playwright-cli click <ref>
```

### 7b. 標準時間を入力（平日分）

1. 「編集」ボタン（標準時間セクション付近の最初のもの）をクリック
2. 以下の値を入力（休憩時間は未入力のままでよい）:
   - 標準開始時間: `19:00`
   - 標準終了時間: `21:00`
3. 「保存」ボタンをクリック

※標準時間は土日を除く平日にのみ一括反映される。土曜日は次のステップで個別入力する。

```bash
playwright-cli snapshot
# 編集ボタンをクリック
playwright-cli click <編集ボタンref>

# snapshot で各 textbox ref を特定
playwright-cli fill <標準開始時間ref> "19:00"
playwright-cli fill <標準終了時間ref> "21:00"
# 標準休憩開始時間・標準休憩終了時間は入力しない

# 保存
playwright-cli click <保存ボタンref>
```

### 8b. 土曜日の時間を個別入力

1. 「編集」ボタンをクリック
2. snapshot でテーブルの土曜日（土）の行を特定
3. 各土曜日の開始時刻に `10:00`、終了時刻に `12:00`、休憩時間に `0:00` を入力
4. 「保存」ボタンをクリック

```bash
playwright-cli snapshot
# 編集ボタンをクリック
playwright-cli click <編集ボタンref>

# snapshot から土曜日の行を特定し、各 textbox ref を取得
# 各土曜日に対して:
playwright-cli fill <開始時刻ref> "10:00"
playwright-cli fill <終了時刻ref> "12:00"
playwright-cli fill <休憩時間ref> "0:00"
# ... すべての土曜日に対して実行

# 保存
playwright-cli click <保存ボタンref>
```

### 9b. 作業内容を入力

1. 「編集」ボタンをクリック
2. snapshot でテーブルの各行を確認し、作業時間が `8:00` 等（0:00 および空欄以外）の日付を特定（平日＋土曜日が対象）
3. 該当日の「作業内容」textbox に `コンテンツ管理システムの設計・開発` を入力
4. 「保存」ボタンをクリック

```bash
playwright-cli snapshot
# 編集ボタンをクリック
playwright-cli click <編集ボタンref>

# snapshot を読み取り、作業時間が発生している行の作業内容 textbox ref を特定
# 各 row の構造: 日付 / 開始時刻 / 終了時刻 / 休憩時間 / 作業内容(textbox) / 作業時間 / 特記事項
# 作業時間セルが 0:00 でない、かつ空でない行が対象（平日＋土曜日）

playwright-cli fill <作業内容ref> "コンテンツ管理システムの設計・開発"
# ... 対象日すべてに対して実行

# 保存
playwright-cli click <保存ボタンref>
```

### 9b. 完了確認

保存後にスクリーンショットを撮影し、ユーザーに結果を表示する。

```bash
playwright-cli screenshot --filename=.playwright-cli/capture/geechs-report-abema-saved.png
```

## 完了

### 10. ブラウザを閉じる

```bash
playwright-cli close
```
