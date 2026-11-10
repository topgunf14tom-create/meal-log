# 食事記録アプリ（個人用）仕様書 / CLAUDE.md

## 0. このファイルについて
Claude Code 向けの開発指示書。リポジトリ直下に置き、ここに書かれた仕様・方針に従って実装すること。
不明点は勝手に仕様を広げず、TODO コメントを残して最小構成で実装する。

---

## 1. 概要
- 目的：あすけんの「食事記録」部分だけを自分用に再現する Android アプリ（APK）
- 利用者：自分（友人へは各自のAPIキーで使う前提でAPKを配布可）
- 主な機能
  1. 食品DB（同梱）の横断検索で記録（チェーン公式値・食品成分表・居酒屋/朝食の定番・登録食品。API不要）
  2. 食事写真（真上＋斜め45°、100円玉を基準物）→ Haiku は料理名候補と量感クラスだけ判定 → 栄養値は食品DBからコードで計算
  3. 栄養成分表示（端末OCR→整合性チェック→Haiku転記）・JANバーコードで登録食品に蓄積
  4. DBに無いチェーン店は公式HPの栄養成分をウェブ検索で取得（結果は端末にキャッシュ）
  ※ 改修仕様の全文は `docs/spec_redesign.md`（2026-11-10）。入力の手間を増やす機能は、精度が上がっても採用しない
  3. 目標カロリー・PFC目標比率の設定
  4. 1日のカロリー・PFCバランス表示
  5. 体重の手入力と推移グラフ
  7. ヘルスコネクト連携（InBody の体重・体脂肪、Strava の運動、歩数を自動取り込みし、消費カロリーを計算）
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
| テーマ | ダーク固定（Astryx の Gothic テーマの色・角丸を `lib/core/theme.dart` に移植）。英数字は同梱の Fustat（assets/fonts、OFL）、日本語は端末のフォント |
| グラフ | CustomPaint（自前描画。外部パッケージ依存を減らすため） |
| 日付 | 自前の日付ヘルパー（lib/core/dates.dart）＋flutter_localizations（ja） |
| QR読み取り | mobile_scanner（InBody 用紙の QR） |
| zip 読み取り | archive（Strava の書き出しの取り込み。別 isolate で処理） |
| 地図 | flutter_map＋latlong2（OpenStreetMap のタイル。運動のルート表示のみ） |
| 共有 | share_plus（画面の一部を PNG にしてテキストと一緒に OS の共有シートへ） |
| ヘルスコネクト | androidx.health.connect:connect-client 1.1.0 を MainActivity（Kotlin）から直接呼び、MethodChannel `meal_log/health` で Dart へ。Kotlin の元ファイルは `tool/android/`、setup スクリプトが android/ にコピー |

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
0-1. **画面下のタブ**（`lib/features/shell/main_shell.dart`）：ホーム・体重・体組成・運動・レポート。ホームは日付を保つため作り直さず、戻ったときに読み直す。ほかのタブは開くたびに作り直す。設定はホームの右上
1. **ホーム（今日）**
   - 日付切替（前日/翌日）
   - 摂取カロリー / 目標カロリー（残り kcal）
   - PFCバランス：実績 g と目標 g の横棒＋比率の円グラフ
   - 食事区分ごとのリスト（朝食・昼食・夕食・間食）
   - 右下 FAB：「記録する」
   - 消費カロリーカード（ヘルスコネクト連携時）：歩数と歩行 kcal、運動（Strava 等）ごとの時間・kcal、合計
   - 連携オンかつ「消費カロリーを目標に上乗せ」がオンなら、目標＝目標kcal＋その日の消費 kcal
   - 未連携でヘルスコネクトがある端末には「連携する」カード（閉じられる）
2. **記録追加**
   - 食事区分選択（時刻から自動推定、変更可）
   - 入力方法：「写真で解析」「栄養成分表示を撮る」「チェーン店メニュー」「お酒」「手入力」
   - 「前回の○食と同じ」：選んだ食事区分の、その日以前で一番新しい食事の料理をそのまま編集画面へ（API不使用）
   - 「よく食べるもの」：最近90日の料理を名前ごとに回数の多い順（値は最新の記録）。複数選んでまとめて編集画面へ（API不使用。`frequent_screen.dart`）
   - 栄養成分表示：パッケージの表示を写真解析と同じモデルで読み取る（`Prompts.label`。推定せず表示の値、100g当たりのみなら amount 100・unit g）
   - お酒：一覧（ビール・発泡酒・糖質オフ・ハイボール・缶ハイボール・サワー・ストロング・ワイン赤白泡・日本酒・焼酎・ウイスキー・梅酒・甘いカクテル・スピリッツ割り）からサイズと杯数（0.5刻み）を選び、まとめて結果編集画面へ。APIは使わない
   - お酒のカロリー＝純アルコール g（ml×度数×0.8）×7＋糖質×4＋タンパク質×4。データは `lib/core/alcohol.dart`。純アルコール合計と1日20gの目安を表示
   - 「その他のお酒」は名前・度数・量・糖質を入力
   - チェーン店メニュー：店名＋メニュー名を入力（写真は任意）
3. **解析結果確認・編集**
   - 料理ごとに：名前 / 量（g または個数） / kcal / P / F / C を表示・編集可能
   - 量を変更したら kcal・PFC を比例計算で自動更新
   - 推定の信頼度（high / medium / low）と情報源（推定 or 公式HP URL）を表示
   - ボタン：「保存」「Sonnetで再解析」
4. **体重**
   - 日付＋体重（kg、小数1桁）入力
   - 折れ線グラフ（7日 / 30日 / 90日切替）
   - 右上「体組成」から体組成の記録へ、走る人のアイコンから運動の記録へ
4-3. **運動の記録**（ホームの消費カロリーカードの履歴ボタン、体重画面から。`lib/features/history/`）
   - データ元：Strava の書き出しの取り込み（strava_activities）＋ヘルスコネクトのエクササイズ。時間が半分以上重なるものは取り込み側を残す（`workouts.dart`）
   - ヘルスコネクト分：重なる記録は1回にまとめ、距離・活動カロリーは同じアプリの DistanceRecord・ActiveCaloriesBurnedRecord のうち時間が重なる分を合計（無ければ METs で推定し「約」）
   - 期間（3か月・1年・すべて）、種目の絞り込み、合計（回数・時間・距離・獲得標高・kcal）、棒グラフ（時間・距離・カロリー・回数・標高 × 週・月・年、直近12区間）、月別の一覧
   - 取り込んだ運動はタップで詳細：地図上のルート（全画面可）、距離・移動時間・ペース/速度・最高速度・獲得標高・経過時間・カロリー・平均/最大心拍、1kmスプリット、ペース・標高・心拍のグラフ（横軸 km）、心拍ゾーン（取り込んだ記録の直近1年の最大心拍を基準に 60/70/80/90%）、ランのベストエフォート
   - ベスト記録画面：ランの距離別（400m〜フル）上位3件、年ごと・種目ごとの合計
   - 30日より前は READ_HEALTH_DATA_HISTORY、距離は READ_DISTANCE が必要。未許可なら「許可する」カード
4-4. **Strava の取り込み**（運動の記録の右上）
   - strava.com の「アカウントのダウンロード」の zip（activities.csv＋activities/ の GPX・TCX・FIT、.gz 可）、activities.csv 単体、1件分の GPX・TCX・FIT を選べる
   - ファイル選択は Kotlin の ACTION_OPEN_DOCUMENT（`pickFile`）でキャッシュにコピー。解析は別 isolate、終わったらコピーを消す
   - CSV の見出しは英語・日本語に対応し、見つからなければ既知の列番号。日時は UTC として読む。値はファイルから計算した値より CSV を優先（距離・移動時間・心拍・カロリー）
   - 点は最大1500点に間引いて保存。スプリット・ベストは間引く前に計算。同じ ID は上書き
   - 解析は `lib/core/activity_files.dart`（GPX・TCX は正規表現、FIT は record・session・sport を自前で読む）、`lib/core/track.dart`（距離・移動時間・獲得標高（3m ヒステリシス）・スプリット・ベスト・心拍ゾーン）、`lib/core/strava_archive.dart`
4-2. **InBody**（体重画面から）
   - 結果用紙の QR（`https://qrcode.inbody.com?IBData=...`）をカメラ・写真・貼り付けで読み取る（mobile_scanner）
   - IBData は固定桁の平文。桁位置は `lib/core/inbody.dart`（InBody270 の実物で照合）。他機種は未対応としてエラー
   - 体重＝除脂肪量＋体脂肪量などの整合性が取れないときは保存しない
   - 確認画面（InBody アプリ風：点数、体成分、筋肉・脂肪、肥満、部位別、体重調整、研究項目、インピーダンス）→ 記録日を選んで保存
   - 保存時オプション：体重記録に反映（既定オン）、目標カロリーを推奨エネルギー摂取量にする（既定オフ）
   - 用紙の日付は本体の時計なので、直近3日以内でなければ記録日の既定は今日
   - 履歴（体組成の記録）：ヘルスコネクトの体重・体脂肪率・除脂肪量（InBody アプリなど）と QR の結果を日ごとにまとめ、期間を選んで推移グラフ（体重・体脂肪率・体脂肪量・除脂肪量・骨格筋量）と一覧。同じ日は QR の結果を優先。QR の行は詳細を開ける
   - QR で取り込んだ日があれば、詳しい項目（点数・BMI・体水分・タンパク質・基礎代謝・内臓脂肪・腹囲・部位別筋肉量/体脂肪量）もグラフにできる
   - 比較画面：QR の記録2回を選び、体成分・部位別・研究項目の値と変化を並べる（増えると良い/減ると良い項目は緑/赤）
4-6. **レポート**（ホームの右上。`lib/features/report/`）
   - 週（月〜日）・月を切り替え、前後へ移動。記録のある日で平均：摂取 kcal、目標との差、記録日数、目標を超えた日数、歩行・運動 kcal、体重の変化、日ごとの摂取の棒グラフ（目標の線つき、超えた日はオレンジ）、PFC の平均 g と比率
   - AI の振り返り：集計の JSON だけを写真解析と同じモデルに送り、200〜300字のコメント（`Prompts.report`、usage の purpose は report）
   - この期間のペースが続いた場合の体重の見込み（下記）
4-7. **体重の見込み**（体重画面：昨日までの14日間、レポート：その期間。`lib/core/forecast.dart`）
   - 食事の記録がある日で平均。消費＝基礎代謝×1.1＋歩行・運動（ヘルスコネクト）。基礎代謝は最新の InBody の値、無ければ体重×22
   - 30日後の変化＝（摂取−消費）×30÷7200。あわせて直近30日の体重の直線回帰の傾き×30（3点以上・7日以上のとき）
4-5. **SNS 共有**：InBody 結果、体組成の推移、InBody の比較、運動のまとめ、運動の詳細（地図つき）、ベスト記録の右上に共有ボタン。表示中のカードを PNG にし、要約テキストと一緒に共有シートへ（`lib/widgets/share_capture.dart`）
5. **設定**
   - 目標カロリー（kcal/日）
   - PFC目標比率（%、合計100になるようバリデーション。初期値 P20 / F25 / C55）
   - Anthropic APIキー（マスク表示、secure storage に保存）
   - モデル設定（写真解析 / チェーン店検索 / 再解析 それぞれのモデル）
   - 画像圧縮設定（長辺 px、JPEG品質）
   - 今月のAPI利用量と概算料金
   - データのエクスポート（JSON）/ インポート
   - ヘルスコネクト：自動取り込みオン/オフ（オンで権限画面）、消費カロリーを目標に上乗せ（既定オン）、身長（空欄なら ヘルスコネクト→最新InBody→170cm の順）、今すぐ同期、ヘルスコネクトの設定を開く
   - 自動バックアップ：保存先のファイルを ACTION_CREATE_DOCUMENT で作ってもらい（Google ドライブも選べる。OAuth 不要）、URI の永続権限を取る。アプリを開いた・戻ったときに前回から20時間以上なら exportAll の JSON を上書き保存。失敗は backup_error に残し設定に表示。「バックアップから戻す」は ACTION_OPEN_DOCUMENT で選んで importAll（設定も置き換わるので開き直してもらう）（`backup_service.dart`）
   - 記録忘れの通知：朝食・昼食・夕食の時刻（既定 9:30・13:30・20:30、個別にオフ可）。7日分を AlarmManager.setAndAllowWhileIdle で予約し、今日すでに記録した区分と過ぎた時刻は除く。アプリを開いた・戻った・記録が変わったときに予約し直す（`core/reminders.dart`、`reminder_service.dart`、Kotlin `ReminderReceiver`）。Android 13 以降は POST_NOTIFICATIONS を求める
   - ホーム画面ウィジェット（Kotlin `MealWidgetProvider`、res は `tool/android/res/`）：今日の残り kcal・摂取/目標・歩数・消費。値はホームの読み込みのたびに SharedPreferences へ送る（`home_widget_updater.dart`）。日付が変わったら「今日はまだ開いていません」

---

## 3-2. 食品DBと写真判定（2026-11 改修。`docs/spec_redesign.md`）
- **役割分担**：モデル（Haiku）は料理名候補・量感クラス・寸法だけ。栄養値は出力させない（`Prompts.judge`、短いキーのJSON `{"d":皿cm,"i":[{"n","c","t","s","g","k","w","h","p"}]}`）。栄養値は食品DBから `core/portion.dart` で決定的に計算
- **DB**：`assets/fooddb/` の4つのJSON（成分表・チェーン・居酒屋・朝食）をそのまま同梱し、起動時に別 isolate で読んでメモリに索引（`core/food_db.dart`、`services/food_repository.dart`）。JSONを差し替えれば更新できる。過去の記録は記録時点の値で固定（meal_items に値を保存、再計算しない）
- **検索**：`core/search_text.dart` で正規化（カタカナ→ひらがな・全角→半角・記号除去）＋同義語グループ。完全一致→前方一致→部分一致、同じ段は利用回数（food_usage）→情報源（登録食品・居酒屋・朝食・チェーン・成分表）の順。空白区切りは全語を含むもの
- **写真の照合**（`core/photo_match.dart`）：主食（ごはん・麺・パン）は成分表の100gあたり値を優先 → 料理名の同義語辞書 `dishCanon` → DB検索 → 語尾を削って再検索（要確認）。チェーン店の商品は写真の照合対象外。確からしさ0.5未満・部分一致は「要確認」で、保存前に確認させる
- **量**：量感クラス 少なめ×0.7／普通×1.0／多め×1.3／大盛×1.6。100gあたりの食品はカテゴリ別の基準量（ごはん・汁物180g、麺220g、主菜100g…）× 係数、1食あたりの食品（辞書）は1食×係数、チェーンは公式のサイズ違い（係数なし）。主食などは計量グラムを入れればクラスより優先
- **調理法**：モデルは調理法コードだけ返し、生の食材にだけ油・砂糖の定型値をコードで加算（炒め＝油大さじ1、揚げ＝吸油10g、煮物＝砂糖小さじ2、焼き＝油小さじ1、和え物・サラダ＝ドレッシング大さじ1）
- **食べた割合**：取り分け（人数で1/N）・残した分は同じ「食べた割合」で、全経路の品目に掛ける（`MealItem.ratio` に記録）
- **kcalのみ公表のチェーン**：PFCは不明（0・`pfc_unknown`）。利用者が成分表の類似食品を選べば、その比率で補完（kcalは公式値のまま、推定と明記）
- **ラベル**：ML Kit（日本語）で端末OCR → `parseLabelText` → Atwater（kcal≒4P+9F+4C、±max(20kcal,15%)）を通れば確認画面、落ちたら Haiku 転記（`Prompts.label`）。確認画面から登録食品（user_foods、JAN付き）へ
- **コスト**：写真は1食1コール（自動の再解析なし。再判定は利用者が選んだときだけ）、固定の指示文に cache_control、訂正は前回の判定JSON＋文章だけ送る（画像を再送しない）、確定した写真の dHash を保存し、ほぼ同じ写真なら前回の内容を出してAPIを使わない
- **いつもの**：記録編集画面の☆で登録 → ホームのチップを1タップで記録（取り消し可）
- **1日の区切り**：設定 → 記録（0〜6時。4なら28時区切り）。ホームの「今日」に使う
- **テキスト書き出し**：ホーム右上の共有ボタン（品目・kcal・PFC・合計・残り）
- 未実装（TODO）：送信前の自動トリミング（皿＋100円玉の範囲。コインの画素径を添付）、皿の直径の登録、DB更新をサーバーから取る口（現在は同梱のみ）、複合料理の標準構成テンプレート

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
| 写真判定・ラベル転記 | `claude-haiku-4-5-20251001` | 安く速い（料理名と量の判定だけなので十分） |
| DBに無いチェーン店のWeb検索 | `claude-sonnet-5` ＋ web_search | 検索結果の読み取り精度 |
| 「再判定」（手動のみ） | `claude-sonnet-5` | 利用者が明示的に選んだときだけ |

- モデルIDは定数ファイル `lib/core/models.dart` にまとめ、設定画面から上書きできるようにする

### 5.3 写真判定リクエスト（3-2 参照）
- system：`Prompts.judge`（cache_control 付き）。user：「1枚目（真上）」画像＋「2枚目（斜め約45°）」画像（任意）＋補足
- `max_tokens`: 500。出力は短いキーの JSON（`core/photo_judge.dart` で読む。栄養数値のキーがあっても読まない）

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
- **weights** に DB version 3 で `source`（manual / health）と `body_fat_pct` を追加。health の行だけ自動取り込みで上書きし、手入力・InBody QR の日は上書きしない
- **activity_days**（DB version 3 で追加）：date(PK), steps, walk_steps, walk_kcal, exercise_kcal, exercises_json, synced_at
- **strava_activities**（DB version 4 で追加）：id(PK, Strava のアクティビティID か file:ファイル名), start_ms, kind, type_label, name, elapsed_s, moving_s, distance_m, elev_gain_m?, avg_hr?, max_hr?, kcal?, max_speed?, has_route, bests_json, detail_json（スプリットと間引いた点 [秒, 緯度, 経度, 標高, 心拍, 距離]）。バックアップの JSON には含めない（zip から取り込み直せるため）
- **DB version 5**：meal_items に food_ref（s:成分表ID / c:チェーン / i:居酒屋 / b:朝食 / u:登録食品）, size_class, ratio, detail, pfc_unknown を追加。user_foods（個人DB・JAN）, food_usage（利用回数・前回の量感クラス）, favorites（いつもの）, photo_hashes（写真の再利用、最新300件）を追加。user_foods・food_usage・favorites はバックアップの JSON に含める
- **inbody_results**（DB version 2 で追加）：id, date, measured_at?, raw(unique, QR文字列), weight_kg, smm_kg, bfm_kg, pbf, score, created_at。詳細表示は raw を解析し直す

---

## 7. 計算ロジック
- 1日の合計：meal_items を日付で集計
- PFC目標 g：
  - P = 目標kcal × P比率 ÷ 4
  - F = 目標kcal × F比率 ÷ 9
  - C = 目標kcal × C比率 ÷ 4
- 実績の PFC 比率：各エネルギー（P×4, F×9, C×4）÷ その合計
- 量の編集時：元の grams（または amount）に対する比で kcal・PFC を按分

### 7.1 ヘルスコネクトと消費カロリー（`lib/core/activity.dart`、`lib/services/activity_sync.dart`）
- 読み取る権限：体重・体脂肪率・除脂肪量・身長・歩数・エクササイズ・活動カロリー・距離・30日より前のデータ（読み取りのみ、書き込みなし）
- 権限リクエスト：Android 14 以降は requestPermissions（OS 組み込みのヘルスコネクト）、13 以前は PermissionController の契約の Intent を startActivityForResult
- 取り込みのタイミング：アプリ起動時・復帰時（5分以内の再実行は省略）、ホームの引っ張り更新・同期ボタン、日付切替でその日のデータが無いとき。バックグラウンド実行はしない
- 体重・体脂肪：前回取り込みの2日前から（初回は30日前から）読み、日ごとに最新の値を weights へ
- 対象日：今日・昨日・表示中の日（30日以内）
- 歩数は区間集計（AggregateRequest、ヘルスコネクト側で重複除去）を使う
- 運動：同じ時間帯に重なる記録は1つにまとめる（Strava と Fit の二重記録対策）
- 歩幅＝身長×0.45、距離 km＝歩数×歩幅÷1000、歩行 kcal＝体重×距離×0.5（体重はその日以前の最新、無ければ60kg）
- 運動中の歩数は歩行から除く。運動 kcal はその時間帯の活動カロリー、無ければ (METs−1)×体重×時間 で推定（表示に「約」）
- 1日全体の活動カロリーは使わない（歩数分と二重計上になるため）

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
- 通信は Claude API と、運動のルート表示の地図タイル（tile.openstreetmap.org、User-Agent にパッケージ名、帰属表示つき）のみ。記録データは外部に送らない（ヘルスコネクトは端末内の読み取りのみ、Strava の取り込みも端末内）。共有はユーザーが共有ボタンを押したときだけ OS の共有シートに渡す
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
- APK は `.github/workflows/build-apk.yml` で自動ビルド。署名鍵は Secret `DEBUG_KEYSTORE_B64`（パスワード android）を android/app/ci.keystore に置き、build.gradle.kts の release を明示的にその鍵で署名する。`~/.android/debug.keystore` に置くだけでは使われずビルドごとに鍵が変わっていた（2026-11-08 修正）。公開前に apksigner で署名の一致を検証
- バージョン番号はビルドごとに増やす（versionCode = 実行番号＋100）
- エクスポート/インポートはクリップボード経由の JSON（写真は含まない）。自動バックアップは同じ JSON をファイルへ
- setup スクリプトは ReminderReceiver・MealWidgetProvider と tool/android/res/ をコピーし、POST_NOTIFICATIONS と receiver を追記する
- ヘルスコネクト連携（7.1）を実装。setup スクリプトがヘルスコネクトの権限・queries・権限説明画面（PermissionsRationaleActivity と activity-alias）・依存ライブラリを追記し、MainActivity を `tool/android/MainActivity.kt` で置き換える
- TODO：バックグラウンドでの定期取り込み（READ_HEALTH_DATA_IN_BACKGROUND）は未対応。30日より前の履歴は履歴画面でのみ読む（自動取り込みは従来どおり直近分）
