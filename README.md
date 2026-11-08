# 食事記録アプリ（Android）

写真を撮るだけでカロリー・PFCを記録する、自分用の食事記録アプリです。
仕様は `CLAUDE.md` を参照してください。

---

## 1. Claude API の導入手順

写真解析とチェーン店検索には Claude API を使います。Claude.ai の Pro / Max 契約とは**別の従量課金**です（目安：1日3食で月100〜300円）。

1. **アカウント作成**
   <https://platform.claude.com/> を開き、Googleアカウントなどでサインアップします。
2. **クレジットを購入**
   左メニューの Settings → **Billing** でクレジットカードを登録し、クレジットを購入します（プリペイド。最低購入額は画面で確認してください）。
   - **自動チャージ（Auto reload）はオフのまま**にしておくと、使いすぎの心配がありません。
3. **利用上限を設定（おすすめ）**
   Settings → **Limits** で月の上限額（例：$5）を設定します。上限に達するとAPIが止まるだけで、請求は増えません。
4. **APIキーを発行**
   **API Keys** → **Create Key** → 名前（例：`meal-log`）を付けて作成し、`sk-ant-` で始まるキーをコピーします。
   **キーは一度しか表示されません。** 失くしたら新しく作り直してください。
5. **アプリに登録**
   アプリの初回起動画面（または 設定 → Claude APIキー）でキーを貼り付け、「接続テストして保存」を押します。
   「接続OK」と出れば完了です。キーは端末の安全な領域（Android Keystore）にだけ保存されます。

**接続テストで出るエラーの意味**

| 表示 | 対処 |
|---|---|
| APIキーが正しくありません（401） | キーの貼り間違い。コピーし直す |
| クレジット残高が不足しています | Billing でクレジットを購入 |
| モデルが見つかりません | 設定 → モデル を「初期値に戻す」 |
| 利用上限に達しました（429） | Limits の上限額を確認 |

**友人に配る場合**：友人それぞれが自分のアカウントでキーを発行して入力すれば、請求は各自に行きます。自分のキーを教えるのは避けてください。

> メニュー名（Billing / Limits / API Keys）は Console の改修で変わることがあります。見つからない場合は Settings 内を探してください。

---

## 2. APK のビルド

この一式には `android/` フォルダが含まれていません。初回に `tool/setup` スクリプトが `flutter create` で生成し、インターネット権限などを自動で追記します。

### 方法A：GitHub Actions（PC に Flutter がなくてもOK）

1. GitHub に**非公開（Private）**リポジトリを作り、このフォルダの中身をすべて push します。
2. **署名鍵を登録**（アップデート時にデータを消さないため。初回だけ）
   Windows の PowerShell で、PC にある Android の署名鍵を Base64 にしてコピーします。
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.android\debug.keystore")) | Set-Clipboard
   ```
   ファイルが無い場合は、JDK の keytool で作成します。
   ```powershell
   keytool -genkeypair -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
   ```
   リポジトリの Settings → Secrets and variables → Actions → **New repository secret** で、
   名前 `DEBUG_KEYSTORE_B64`、値に貼り付けて保存します。
3. **Actions** タブ → **Build APK** → **Run workflow**（main への push でも自動実行）。
4. 完了したら実行結果の **Artifacts** から `meal_log-apk` をダウンロードし、中の `app-release.apk` をスマホに入れます。

### 方法B：Windows PC でビルド

Flutter SDK と Android Studio（Android SDK）が入っている前提です。

```powershell
cd meal_log
powershell -ExecutionPolicy Bypass -File tool\setup.ps1
flutter pub get
flutter test
flutter build apk --release
```

出力：`build\app\outputs\flutter-apk\app-release.apk`
スマホを USB 接続して `flutter install` でも入れられます。

### ビルドでつまずいたら

この一式はビルド環境の外で書いたため、Flutter やパッケージのバージョンによっては初回ビルドで小さな修正が要る場合があります。
このフォルダで Claude Code を起動し、「`flutter build apk` のエラーを直して」と頼めば、CLAUDE.md を読んだうえで修正してくれます。
パッケージのバージョンが古いと言われたら `flutter pub upgrade --major-versions` を試してください。

---

## 3. インストールと使い方

1. APK をスマホに送り（Google ドライブ等）、タップしてインストール。「提供元不明のアプリ」の許可を求められたら許可します。
2. 初回起動の案内に沿って APIキーと目標カロリーを設定します。
3. ホームの「記録する」→
   - **写真で解析**：撮影すると Haiku が料理・量・カロリー・PFCを推定。内容を直して保存。精度が気になるときは「Sonnetで再解析」
   - **チェーン店メニュー**：店名とメニュー名を入力すると、公式サイトの栄養成分を検索。公式データは端末に保存され、次回からは無料
   - **手入力**：自分で入力
4. 右上のアイコンから **体重**（記録とグラフ）と **設定**（目標・APIキー・モデル・画像圧縮・今月の利用料・バックアップ）を開けます。

**バックアップ**：設定 → データ → エクスポートで、全記録を JSON としてクリップボードにコピーできます。機種変更や再インストールの前にメモアプリ等へ貼って保管してください（写真は含まれません）。

---

## 4. フォルダ構成

```
lib/
  main.dart               起動・初回案内の判定
  app_services.dart       DB・設定・APIの共有
  core/                   モデルID、料金、PFC計算、日付など
  data/                   SQLite（app_db.dart）、設定、データ型
  services/               Claude API、画像圧縮、解析・チェーン店検索
  features/               画面（home / record / result_edit / weight / settings / onboarding）
  widgets/                PFCバー・円グラフ、体重グラフ、目標フォーム
test/                     JSON解析・PFC計算・料金計算・キー正規化のテスト
tool/setup.sh, setup.ps1  android/ の生成と設定追記
.github/workflows/        APK 自動ビルド
```
