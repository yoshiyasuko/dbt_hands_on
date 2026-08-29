# モデルカタログ

全13モデルのカラム・内容・型の一覧。型はBigQueryの `INFORMATION_SCHEMA.COLUMNS` から取得した**実際の型**(2026-08-25時点)。

- 物理名ルール: `int__` / `mart__` prefixのモデルは、`generate_alias_name` マクロによりBigQuery上ではprefixを除いた物理名になる(例: `int__cleansed_orders` → `cleansed_orders`)。`ref()` ではモデル名(prefix付き)を使う
- マテリアライズ: staging=view / intermediate=table / mart=table(`dbt_project.yml` の層設定)。ただし `int__cleansed_orders` と全martモデルはモデル内 `config()` でincremental(insert_overwrite)に上書きされている(洗い替え窓は各セクション参照)

## 依存関係の全体像

```
sources(thelook_ecommerce): orders, order_items, events, products, users
  ├─ stg__orders ──┐
  ├─ stg__order_items ─┼─ int__cleansed_orders ─┬─ mart__daily_sales
  ├─ stg__products ──┘                          ├─ int__daily_user_sales ─┐
  ├─ stg__events ── int__daily_registered_user_types ─┬──────────────────┼─ mart__daily_kpis
  │                                                   └─ int__monthly_registered_user_types ─(+ int__cleansed_orders)─ mart__monthly_department_brand_sales
  └─ stg__users ──────────────(+ int__daily_user_sales)─ mart__monthly_kpis
```

---

## staging層(view)

BigQuery公開データセット `bigquery-public-data.thelook_ecommerce` を `select *` でそのまま参照するビュー。カラム構成はソースと同一。

### stg__orders — 注文データ

グレイン: 1行 = 1注文(`order_id` 一意)。

| カラム | 型 | 内容 |
|---|---|---|
| order_id | INT64 | 注文ID |
| user_id | INT64 | 注文したユーザーのID |
| status | STRING | 注文ステータス(Shipped / Complete / Processing / Cancelled / Returned) |
| gender | STRING | 注文者の性別(F / M) |
| created_at | TIMESTAMP | 注文日時(UTC) |
| returned_at | TIMESTAMP | 返品日時(返品時のみ) |
| shipped_at | TIMESTAMP | 発送日時 |
| delivered_at | TIMESTAMP | 配達完了日時 |
| num_of_item | INT64 | 注文内の商品点数 |

### stg__order_items — 注文詳細データ

グレイン: 1行 = 1注文明細(`id` 一意)。1注文に複数明細が紐づく。

| カラム | 型 | 内容 |
|---|---|---|
| id | INT64 | 注文明細ID |
| order_id | INT64 | 注文ID(stg__ordersへの参照) |
| user_id | INT64 | ユーザーID |
| product_id | INT64 | 商品ID(stg__productsへの参照) |
| inventory_item_id | INT64 | 在庫アイテムID |
| status | STRING | 明細のステータス(accepted_valuesテスト対象: Shipped / Complete / Processing / Cancelled / Returned) |
| created_at | TIMESTAMP | 明細作成日時(UTC) |
| shipped_at | TIMESTAMP | 発送日時 |
| delivered_at | TIMESTAMP | 配達完了日時 |
| returned_at | TIMESTAMP | 返品日時(返品時のみ) |
| sale_price | FLOAT64 | 販売価格(USD) |

### stg__events — イベントデータ

グレイン: 1行 = 1イベント(`id` 一意)。**未ログインイベントは `user_id` がNULL**(アクセス分析では除外して使う)。

| カラム | 型 | 内容 |
|---|---|---|
| id | INT64 | イベントID |
| user_id | INT64 | ユーザーID(未ログイン時はNULL) |
| sequence_number | INT64 | セッション内のイベント連番 |
| session_id | STRING | セッションID |
| created_at | TIMESTAMP | イベント発生日時(UTC) |
| ip_address | STRING | IPアドレス |
| city | STRING | 市区町村 |
| state | STRING | 州・都道府県 |
| postal_code | STRING | 郵便番号 |
| browser | STRING | ブラウザ |
| traffic_source | STRING | 流入元 |
| uri | STRING | アクセスされたURI |
| event_type | STRING | イベント種別(product / department / cart / purchase / cancel / home) |

### stg__products — 商品データ

グレイン: 1行 = 1商品(`id` 一意)。マスタのため鮮度チェック対象外。

| カラム | 型 | 内容 |
|---|---|---|
| id | INT64 | 商品ID |
| cost | FLOAT64 | 原価(USD) |
| category | STRING | 商品カテゴリ |
| name | STRING | 商品名 |
| brand | STRING | ブランド名 |
| retail_price | FLOAT64 | 小売価格(USD) |
| department | STRING | 部門(Men / Women) |
| sku | STRING | SKUコード |
| distribution_center_id | INT64 | 配送センターID |

### stg__users — ユーザーデータ

グレイン: 1行 = 1ユーザー(`id` 一意)。ユーザーマスタ(登録情報・属性)。

| カラム | 型 | 内容 |
|---|---|---|
| id | INT64 | ユーザーID |
| first_name | STRING | 名 |
| last_name | STRING | 姓 |
| email | STRING | メールアドレス |
| age | INT64 | 年齢 |
| gender | STRING | 性別 |
| state | STRING | 州・都道府県 |
| street_address | STRING | 住所 |
| postal_code | STRING | 郵便番号 |
| city | STRING | 市区町村 |
| country | STRING | 国 |
| latitude | FLOAT64 | 緯度 |
| longitude | FLOAT64 | 経度 |
| traffic_source | STRING | 流入元 |
| created_at | TIMESTAMP | ユーザー登録日時(UTC) |
| user_geom | GEOGRAPHY | ユーザーの位置情報(ジオメトリ) |

---

## intermediate層(table)

### int__cleansed_orders(物理名: cleansed_orders)— クレンジング済み注文明細

グレイン: 1行 = 1注文明細。orders × order_items(INNER JOIN)⟕ products。キャンセル・返品(`status in ('Cancelled', 'Returned')`)を除外。
設定: `order_time_jst` で日単位パーティション、`user_id` でクラスタリング。incremental(insert_overwrite)で直近7日(JST・当日含む)の日パーティションを洗い替え。

| カラム | 型 | 内容 |
|---|---|---|
| order_id | INT64 | 注文ID |
| user_id | INT64 | ユーザーID |
| order_time_jst | DATETIME | 注文日時(JST変換済み。`datetime(created_at, 'Asia/Tokyo')`) |
| product_id | INT64 | 商品ID |
| inventory_item_id | INT64 | 在庫アイテムID |
| sales_jpy | INT64 | 売上金額(日本円。`sale_price × 150` を四捨五入) |
| product_category | STRING | 商品カテゴリ |
| product_name | STRING | 商品名 |
| product_brand | STRING | 商品ブランド |
| product_department | STRING | 商品部門 |

### int__daily_registered_user_types(物理名: daily_registered_user_types)— 日次ユーザータイプ

グレイン: 1行 = ユーザー × アクセス日(eventsから `user_id IS NOT NULL` のアクセス日をdistinctで抽出)。LAG/LEADで前回・次回アクセス日を参照する付与型モデル。

| カラム | 型 | 内容 |
|---|---|---|
| user_id | INT64 | ユーザーID |
| date | DATE | アクセス日(JST) |
| user_type | STRING | ユーザータイプ(新規=初アクセス / 復帰=前回アクセスから15日以上 / 既存=それ以外) |
| d1_access_flg | INT64 | 1日後アクセスフラグ(0/1。次回アクセスがちょうど翌日) |
| d1_3_access_flg | INT64 | 1〜3日後アクセスフラグ(0/1。累積型: d1を包含) |
| d1_7_access_flg | INT64 | 1〜7日後アクセスフラグ(0/1。累積型) |
| d1_14_access_flg | INT64 | 1〜14日後アクセスフラグ(0/1。累積型) |

### int__daily_user_sales(物理名: daily_user_sales)— 日次ユーザー売上

グレイン: 1行 = ユーザー × アクセス日(int__daily_registered_user_types基準。**アクセス日ベースなので、アクセスのない日の購入は含まれない**)。RANGEウィンドウ(`unix_date`)でカレンダー日基準の過去売上を付与。

| カラム | 型 | 内容 |
|---|---|---|
| user_id | INT64 | ユーザーID |
| date | DATE | アクセス日(JST) |
| sales | FLOAT64 | 当日売上(円。購入なしは0) |
| past_d30_sales | FLOAT64 | 過去30日間売上(当日除く直近30カレンダー日。円) |
| past_all_sales | FLOAT64 | 過去累計売上(当日除く。円) |
| past_d30_payment_segment | STRING | 30日間課金セグメント(a_50,001円~ / b_30,001円~50,000円 / c_10,001円~30,000円 / d_5,001円~10,000円 / e_3,001円~5,000円 / f_1,001円~3,000円 / g_1円~1,000円 / h_0円) |
| payment_experience_flg | INT64 | 課金経験フラグ(0/1。過去累計売上 > 0) |

### int__monthly_registered_user_types(物理名: monthly_registered_user_types)— 月次ユーザータイプ

グレイン: 1行 = ユーザー × アクセス月(日次ユーザータイプを月単位にロールアップ)。優先順位: 月内に新規あり→新規、復帰あり→復帰、それ以外→既存。

| カラム | 型 | 内容 |
|---|---|---|
| month | DATE | 月(月初日。`date_trunc(date, month)`) |
| user_id | INT64 | ユーザーID |
| user_type | STRING | ユーザータイプ(新規 / 復帰 / 既存) |

---

## mart層(table)

### mart__daily_sales(物理名: daily_sales)— 日次売上

グレイン: 1行 = 日付(`date` にunique・not_nullテストあり)。int__cleansed_ordersを日次集計。
設定: `date` で日単位パーティション。incremental(insert_overwrite)で直近7日(当日含む)を洗い替え。

| カラム | 型 | 内容 |
|---|---|---|
| date | DATE | 売上日(JST) |
| sales | INT64 | 売上金額合計(円) |
| payment_uu | INT64 | 購入ユーザー数(distinct) |
| arppu | FLOAT64 | 課金ユーザー1人あたり平均売上(sales ÷ payment_uu、小数第1位丸め) |

### mart__daily_kpis(物理名: daily_kpis)— 日次KPI

グレイン: 1行 = 日付 × 詳細ユーザータイプ × 30日間課金セグメント(複合グレイン。`date` 単独では一意でない)。材料はユーザー×日(int__daily_registered_user_types ⟕ int__daily_user_sales)。`date` のnot_nullテストは直近7日のみ対象(where config)。
設定: `date` で日単位パーティション。incremental(insert_overwrite)で直近7日(当日含む)を洗い替え。

| カラム | 型 | 内容 |
|---|---|---|
| date | DATE | 日付(JST) |
| detail_user_type | STRING | 詳細ユーザータイプ(新規 / 復帰無課金 / 復帰課金経験 / 既存無課金 / 既存課金経験) |
| past_d30_payment_segment | STRING | 30日間課金セグメント(int__daily_user_salesのa〜hの8分類) |
| dau | INT64 | DAU(distinct user_id) |
| new_uu | INT64 | 新規UU |
| d1_access_uu | INT64 | 1日後アクセスUU |
| d1_3_access_uu | INT64 | 1〜3日後アクセスUU(累積型) |
| d1_7_access_uu | INT64 | 1〜7日後アクセスUU(累積型) |
| d1_14_access_uu | INT64 | 1〜14日後アクセスUU(累積型) |
| payment_uu | INT64 | 購入UU(当日売上 > 0のdistinctユーザー数) |
| sales | FLOAT64 | 売上(円。アクセス日ベースのため注文全体は捕捉しない — 既知のデータ特性) |

### mart__monthly_department_brand_sales(物理名: monthly_department_brand_sales)— 月次部門別ブランド売上

グレイン: 1行 = 月 × ユーザータイプ × 部門 × ブランド。注文明細に月・ユーザータイプを付与(INNER JOIN)し、月×部門×ブランドの購入UUが10人未満のブランドは「その他」に付け替えてから集計。
設定: `month` で月単位パーティション。incremental(insert_overwrite)で「直近7日を含む月」を月初から丸ごと洗い替え。

| カラム | 型 | 内容 |
|---|---|---|
| month | DATE | 月(月初日) |
| user_type | STRING | ユーザータイプ(新規 / 復帰 / 既存) |
| department | STRING | 部門名(Men / Women) |
| brand | STRING | ブランド名(購入UU10人未満は「その他」) |
| sales | FLOAT64 | 売上(円) |
| payment_uu | INT64 | 購入UU(distinct) |

### mart__monthly_kpis(物理名: monthly_kpis)— 月次国別KPI

グレイン: 1行 = 月 × 国(国内 / US / その他海外 / 不明)。材料はユーザー×月(int__daily_user_salesを月次集計し、stg__usersの国を付与)。四分位数は**課金者(当月sales > 0)の月次課金額**の分布を `percentile_cont`(月×国パーティション)で算出。
設定: `month` で月単位パーティション。incremental(insert_overwrite)で「直近7日を含む月」を月初から丸ごと洗い替え。

| カラム | 型 | 内容 |
|---|---|---|
| month | DATE | 月(月初日) |
| country | STRING | 国(国内 / US / その他海外 / 不明) |
| mau | INT64 | MAU(月内アクセスUU) |
| sales | FLOAT64 | 売上(円) |
| payment_uu | INT64 | 課金UU(月内sales > 0のdistinctユーザー数) |
| arppu | FLOAT64 | ARPPU(sales ÷ payment_uu、小数第1位丸め) |
| sales_q1 | FLOAT64 | 課金者の月次課金額 第1四分位数(円) |
| sales_q2 | FLOAT64 | 課金者の月次課金額 第2四分位数=中央値(円) |
| sales_q3 | FLOAT64 | 課金者の月次課金額 第3四分位数(円) |

---

## 補足: 型に関する注意点

- **`sales` の型がモデル間で不統一**: mart__daily_sales は INT64、mart__daily_kpis / mart__monthly_department_brand_sales / int__daily_user_sales は FLOAT64(ウィンドウ集計・除算の都合でfloat64にcastしているため)。金額の実体はどれも円の整数値
- 日時カラムの使い分け: staging=TIMESTAMP(UTC) / int__cleansed_orders=DATETIME(JST) / 日次・月次モデル=DATE(JST)
- 0/1フラグ(`*_flg`)はBOOLではなくINT64(`sum()` でそのままUU集計できるようにするため)
