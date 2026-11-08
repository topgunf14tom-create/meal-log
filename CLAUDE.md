# 食事記録アプリ（個人用）仕様書 / CLAUDE.md

## 0. このファイルについて
Claude Code 向けの開発指示書。リポジトリ直下に置き、ここに書かれた仕様・方針に従って実装すること。
不明点は勝手に仕様を広げず、TODO コメントを残して最小構成で実装する。

---

## 1. 概要
- 目的：あすけんの「食事記録」部分だけを自分用に再現する Android アプリ（APK）
- 利用者：自分（友人へは各自のAPIキーで使う前提でAPKを配布可）
- 主な機能
  1. 食事写真を撮影 → 圧縮 → Claude API で料理名・量・カロリー・PFC を推定して記録
  2. チェーン店メニューは公式HPの栄養成分をウェブ検索で取得して記録（結果は端末にキャッシュ）
  3. 目標カロリー・PFC目標比率の設定
  4. 1日のカロリー・PFCバランス表示
  5. 体重の手入力と推移グラフ
- UI・ロゴ・食品DBはあすけんを模倣しない（オリジナルのシンプルなデザイン）

---

## 2. 技術スタック
| 項目 | 採用 |
|---|---|
| フレームワーク | Flutter（Dart 3 系、最新安定版） |
| 対象OS | Android（minSdk 26 / targetSdk 最新）、iOS（16 以上） |
| 外部リンク | url_launcher |
| 状態管理 | StatefulWidget＋共有サービス（AppServices）。規模が大きくなったら Riverpod へ移行 |
| ローカルDB | sqflite（SQLite。コード生成不要のため drift から変更） |
| HTTP | http |
| カメラ/画像選択 | image_picker |
| 画像圧縮 | flutter_image_compress |
| APIキー保存 | flutter_secure_storage |
| グラフ | CustomPaint（自前描画。外部パッケージ依存を減らすため） |
| 日付 | 自前の日付ヘルパー（lib/core/dates.dart）＋flutter_localizations（ja） |

---

## 3. 画面構成
0. **初回起動の案内（オンボーディング）**
   - APIキーが未保存のときだけ表示。保存済みなら直接ホームへ
   - ページ1：アプリの説明（写真でカロリー・PFCを記録、データは端末内のみ保存）
   - ページ2：APIキーの取得手順
     1. platform.claude.com でアカウント作成
     2. Billing でクレジットを購入（少額でOK）
     3. API Keys でキーを発行してコピー
     - 「Consoleを開く」ボタン（外部ブラウザで開く、url_launcher）
     - 料金の目安（月100〜300円程度、利用者本人のアカウントに請求される旨）を表示
   - ページ3：APIキー入力
     - 貼り付けボタン、表示/非表示切替
     - 形式チェック（`sk-ant-` で始まるか）
     - 「接続テスト」：Haiku に短いテキストを1回送り、成功/失敗（キー誤り・残高不足・通信エラー）を分かりやすく表示
     - テスト成功で保存して次へ
   - ページ4：目標カロリー・PFC比率の初期設定（スキップ可）
   - 「あとで設定」を選んだ場合は手入力のみ使える状態でホームへ。写真解析を押したときに再度キー入力を促す
   - 設定画面からいつでも再表示・キー変更・キー削除ができる
1. **ホーム（今日）**
   - 日付切替（前日/翌日）
   - 摂取カロリー / 目標カロリー（残り kcal）
   - PFCバランス：実績 g と目標 g の横棒＋比率の円グラフ
   - 食事区分ごとのリスト（朝食・昼食・夕食・間食）
   - 右下 FAB：「記録する」
2. **記録追加**
   - 食事区分選択（時刻から自動推定、変更可）
   - 入力方法：「写真で解析」「チェーン店メニュー」「手入力」
   - チェーン店メニュー：店名＋メニュー名を入力（写真は任意）
3. **解析結果確認・編集**
   - 料理ごとに：名前 / 量（g または個数） / kcal / P / F / C を表示・編集可能
   - 量を変更したら kcal・PFC を比例計算で自動更新
   - 推定の信頼度（high / medium / low）と情報源（推定 or 公式HP URL）を表示
   - ボタン：「保存」「Sonnetで再解析」
4. **体重**
   - 日付＋体重（kg、小数1桁）入力
   - 折れ線グラフ（7日 / 30日 / 90日切替）
5. **設定**
   - 目標カロリー（kcal/日）
   - PFC目標比率（%、合計100になるようバリデーション。初期値 P20 / F25 / C55）
   - Anthropic APIキー（マスク表示、secure storage に保存）
   - モデル設定（写真解析 / チェーン店検索 / 再解析 それぞれのモデル）
   - 画像圧縮設定（長辺 px、JPEG品質）
   - 今月のAPI利用量と概算料金
   - データのエクスポート（JSON）/ インポート

---

## 4. 画像圧縮
- 撮影直後、API送信前に必ず圧縮する
- 既定値：長辺 **1024px**、JPEG 品質 **80**、EXIF（位置情報含む）を削除
- 目安：1枚あたり約 1,200〜1,600 画像トークン
- 設定画面で長辺（768 / 1024 / 1280）と品質（60〜90）を変更可能
- 元画像はアプリ内に保存しない（圧縮後画像のみ、サムネイル用にアプリ専用領域へ保存）

---

## 5. Claude API 連携

### 5.1 共通
- エンドポイント：`POST https://api.anthropic.com/v1/messages`
- ヘッダー：`x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- 画像は base64、`media_type: image/jpeg`
- タイムアウト 60 秒、失敗時は1回だけ自動リトライ
- レスポンスの `usage`（input_tokens / output_tokens / web_search_requests）を毎回 DB に記録する

### 5.2 モデルの使い分け（既定値、設定で変更可）
| 用途 | モデル | 理由 |
|---|---|---|
| 写真解析（通常） | `claude-haiku-4-5-20251001` | 安く速い |
| チェーン店メニュー検索 | `claude-sonnet-5` ＋ web_search | 検索結果の読み取り精度 |
| 「Sonnetで再解析」 | `claude-sonnet-5` | 手動で精度を上げたいとき |

- モデルIDは定数ファイル `lib/core/models.dart` にまとめ、設定画面から上書きできるようにする

### 5.3 写真解析リクエスト
- system プロンプト（要旨）
  - あなたは管理栄養士。写真の料理を識別し、量を推定して栄養価を算出する
  - 日本の一般的な1人前・日本食品標準成分表の値を基準にする
  - 出力は **JSONのみ**（前置き・コードブロック禁止）、スキーマは 5.5 に従う
  - 見えない調味料・油も一般的な量で加算する
- user：圧縮画像＋任意の補足テキスト（例：「ご飯は小盛り」）
- `max_tokens`: 1024

### 5.4 チェーン店メニュー検索リクエスト
- 先にローカルキャッシュ（`chain_menu_cache`）を「店名＋メニュー名（正規化）」で検索。ヒットしたらAPIを呼ばない
- ミス時のみ API を呼ぶ
  - tools：`{"type": "web_search_20260209", "name": "web_search", "max_uses": 3}`
  - 指示：公式サイトの栄養成分表を優先。見つからなければ信頼できる情報源、それもなければ推定値とし `source_type` を `estimate` にする
  - 写真が添付されていればサイズ・トッピングの判別に使う
  - 出力は 5.5 のスキーマの JSON、`source_url` を必ず含める
- 取得結果（`source_type: official`）をキャッシュに保存
- 正規化：全角半角統一、空白除去、小文字化

### 5.5 レスポンス JSON スキーマ
```json
{
  "items": [
    {
      "name": "牛丼 並盛",
      "amount": 1,
      "unit": "杯",
      "grams": 380,
      "kcal": 635,
      "protein_g": 20.2,
      "fat_g": 20.9,
      "carbs_g": 92.8,
      "confidence": "high",
      "source_type": "official",
      "source_url": "https://..."
    }
  ],
  "note": "補足（任意）"
}
```
- `confidence`: `high` / `medium` / `low`
- `source_type`: `official` / `reference` / `estimate`
- パース失敗時：最初の `{` から最後の `}` までを抽出して再パース。それでも失敗したらエラー表示し、手入力に切り替えられるようにする

### 5.6 料金計算（概算表示用）
- 単価は `lib/core/pricing.dart` に定数で持つ（USD / 100万トークン）
  - Haiku 4.5：入力 1.0 / 出力 5.0
  - Sonnet 5：入力 2.0 / 出力 10.0
  - Web検索：0.01 USD / 回
- 設定の為替レート（初期値 150 円/USD）で円換算し、今月合計を表示
- 単価は変わる可能性があるので設定画面から編集可能にする

---

## 6. データモデル（SQLite / sqflite）
- **meals**：id, date, meal_type(breakfast/lunch/dinner/snack), created_at, photo_path?, model_used, note?
- **meal_items**：id, meal_id, name, amount, unit, grams?, kcal, protein_g, fat_g, carbs_g, confidence, source_type, source_url?
- **weights**：id, date(unique), weight_kg
- **goals**：id, start_date, target_kcal, p_ratio, f_ratio, c_ratio（履歴を残し、日付時点の目標を参照）
- **chain_menu_cache**：id, store_key, menu_key, display_name, 栄養値一式, source_url, fetched_at
- **api_usage**：id, timestamp, model, purpose(photo/chain/reanalyze), input_tokens, output_tokens, web_search_requests, cost_usd

---

## 7. 計算ロジック
- 1日の合計：meal_items を日付で集計
- PFC目標 g：
  - P = 目標kcal × P比率 ÷ 4
  - F = 目標kcal × F比率 ÷ 9
  - C = 目標kcal × C比率 ÷ 4
- 実績の PFC 比率：各エネルギー（P×4, F×9, C×4）÷ その合計
- 量の編集時：元の grams（または amount）に対する比で kcal・PFC を按分

---

## 8. ディレクトリ構成
```
lib/
  main.dart
  core/        # models.dart, pricing.dart, theme.dart, constants
  data/        # app_db.dart（sqflite）, app_settings.dart, entities.dart
  services/    # claude_client.dart, image_service.dart, nutrition_service.dart
  features/
    home/
    record/
    result_edit/
    weight/
    settings/
  widgets/     # 共通UI（PFCバー、カロリーリングなど）
test/
```

---

## 9. 非機能要件・ルール
- APIキーはソースコード・ログ・Git に絶対に含めない
- 通信は Claude API のみ。その他の外部送信はしない
- オフラインでも記録の閲覧・手入力・体重記録はできること
- 日本語UI、数値は kcal は整数、g は小数1桁
- 各サービス層にユニットテストを書く（JSONパース、PFC計算、料金計算、キャッシュ正規化）

---

## 10. 開発ステップ
1. プロジェクト作成、DBスキーマ、手入力での記録とホーム表示、初回起動の案内画面（APIキー入力・接続テスト）
2. 目標カロリー・PFC比率設定と PFC バランス表示
3. 体重記録とグラフ
4. 画像圧縮＋Haiku での写真解析＋結果編集画面
5. チェーン店検索（Sonnet＋web_search）とキャッシュ
6. Sonnet 再解析ボタン、API利用量・料金表示
7. エクスポート/インポート、仕上げ

各ステップ完了時に `flutter analyze` と `flutter test` を通すこと。

## 11. ビルド
- デバッグ：`flutter run`
- APK：`flutter build apk --release`（署名は自分用の keystore。keystore と key.properties は .gitignore）
- 出力：`build/app/outputs/flutter-apk/app-release.apk`

### iOS
- コードは Android と共通。プラットフォーム固有の分岐は最小限にする
- `ios/Runner/Info.plist` に以下を追加
  - `NSCameraUsageDescription`：食事の写真を撮影するために使用します
  - `NSPhotoLibraryUsageDescription`：食事の写真を選択するために使用します
- flutter_secure_storage は Keychain を使用（追加設定不要）
- ビルドは Mac＋Xcode 必須：`flutter build ipa`
- 実機への配布は Xcode から直接インストール、または TestFlight を使う

## 12. 実装状況
- ステップ1〜7を一通り実装済み。ビルドは `tool/setup.sh`（Windowsは `tool/setup.ps1`）で android/ を生成してから行う
- android/・ios/ はリポジトリに含めず、setup スクリプトで生成・設定追記する（INTERNET権限、https の queries、minSdk 26、iOSの利用目的文言）
- APK は `.github/workflows/build-apk.yml` で自動ビルド。署名鍵は Secret `DEBUG_KEYSTORE_B64` から復元
- エクスポート/インポートはクリップボード経由の JSON（写真は含まない）
