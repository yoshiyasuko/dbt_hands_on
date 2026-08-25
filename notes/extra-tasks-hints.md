# dbt演習追加課題の読み解きとヒント

出典: 「BNXデータエンジニア養成メニュー202511」の「dbt演習追加課題」セクション。
ecommerce_dbt_bootcamp(このリポジトリ)で作成したテーブルを元に分析調査する。**リポジトリに無い情報はデータレイク(`bigquery-public-data.thelook_ecommerce`)から取得して紐付ける**(users テーブルなど)。

---

## 課題1: モデルのincremental化

**やること**: `materialized='incremental'` + `incremental_strategy='insert_overwrite'` で、直近7日分のパーティションだけを洗い替えるモデルに変える。mart__daily_sales → mart__daily_kpis / mart__monthly_department_brand_sales → int__cleansed_orders の順。

**鍵となる概念**
- `insert_overwrite` は「対象パーティションを丸ごと差し替える」戦略。**モデルがパーティションテーブルであることが前提**なので、mart__daily_sales等にはまず `partition_by`(date列)を追加する必要がある
- `is_incremental()` マクロで「2回目以降の実行」だけにWHEREを効かせる:
  ```sql
  {% if is_incremental() %}
  where date >= date_sub(current_date('Asia/Tokyo'), interval 7 day)
  {% endif %}
  ```
- 処理容量はdbtログの `xx processed` や BigQueryコンソールのジョブ履歴で確認
- **冪等性の確認**(繰り返し実行で行が増えない/欠けない)は、実行→件数記録→再実行→件数比較。insert_overwriteはパーティション差し替えなので二重INSERTにならないのがポイント(merge戦略との違い)

**月次グレインのモデル(mart__monthly_department_brand_sales)の注意**
- 「直近7日」をそのままWHEREに書けるのは、フィルタ窓とパーティション粒度が一致する日次モデルだけ。insert_overwriteはパーティションを丸ごと差し替えるため、SELECTは**そのパーティションの完全な中身**を返す必要がある
- 7日フィルタのままだと当月パーティションが「直近7日分だけで集計した月」に置き換わり、月合計と「その他」ブランド判定(UU10人未満)が過少になる。実行は成功し、繰り返し実行しても同じ結果になる(**冪等だが誤り**)ため、冪等性チェックでは検出できない
- 正しい読み替えは「直近7日に注文が入った月を、月ごと丸ごと再計算」:
  ```sql
  -- partition_by は {"field": "month", "data_type": "date", "granularity": "month"}
  {% if is_incremental() %}
  where date(order_time_jst) >= date_trunc(date_sub(current_date('Asia/Tokyo'), interval 7 day), month)
  {% endif %}
  ```
  月初1〜7日の実行では窓が月境界をまたぎ、前月も自動的に再計算対象になる
- 一般則: **洗い替えのフィルタ窓は「新データが影響するパーティションの完全な中身を作れる範囲」まで広げる**。1-9(lookback)と同じ構図で、影響範囲が月単位なら月まで広げれば成立し、全履歴・未来に及ぶなら不向きとなる

**1-8. int__cleansed_ordersで処理容量が減らない理由(考察問題)**
- ヒント: incrementalで減るのは「**読む側のスキャン量**」ではなく、WHEREで絞った結果を書く量。読む側のスキャン量が減るのは**上流がパーティションテーブルでプルーニングが効く場合だけ**
- mart__daily_salesの上流(cleansed_orders)はorder_time_jstパーティション済み → 絞れば読みも減る
- int__cleansed_ordersの上流は生ソース(bigquery-public-dataの非パーティションテーブル) → どうWHEREしても全件スキャン

**1-9. int__daily_registered_user_typesをincremental化する問題(考察問題)**
- ヒント: このモデルは `lag()` / `lead()` を使う。直近7日分だけ処理すると:
  - `lag`(前回アクセス日)は7日より前の履歴が見えず「新規/復帰」判定が壊れる
  - `lead`(次回アクセス日)は**未来のデータが来て初めて過去の行のフラグが確定する**。つまり「7日前の行のd1_14_access_flgは今日のアクセスで変わり得る」— 直近7日の洗い替えでは過去パーティションの更新が漏れる
- 「ウィンドウ関数で全履歴/未来を参照するモデルはincrementalに不向き。やるならlookback(処理窓を判定に必要な期間だけ広げる)設計が要る」が結論の骨子

## 課題2: Dataform

**やること**: GCPコンソールのDataform(無料)でthelook ecommerceの同等パイプラインを作り、dbt版のmartと突き合わせる。

**ヒント**
- DataformはSQLX形式。`ref()` や依存グラフなどdbtと概念はほぼ同じ(config { type: "table" } など)
- 差分確認は `EXCEPT DISTINCT` を双方向に実行(A except B / B except A が両方0行なら一致)、または日次売上同士をJOINして差分列を出す
- 売上比較グラフはLooker Studioで「dbt版daily_salesとDataform版を日付でJOINしたビュー」を作って2系列の時系列グラフに

## 課題3: Terraform

**やること**: 公式チュートリアル(gcp-get-started)を一通り。

**ヒント**: `provider "google"`、`terraform init/plan/apply/destroy` のサイクルと「状態(tfstate)」の概念が本体。認証は `gcloud auth application-default login`(dbtと同じADC)。**作ったリソースは必ずdestroy**。

## 課題4: dbt-osmosis

**やること**: YAMLの自動生成・カラムdescription伝播ツールを試す。

**ヒント**
- `pip install dbt-osmosis` → `dbt-osmosis yaml refactor` が基本。上流のdescriptionが下流モデルのYAMLへ自動伝播される(このプロジェクトで手書きしてきた作業の自動化)
- **dbt-core 1.12とは互換性がない可能性**(資料は1.9系OKと明記)。既存venvを壊さないよう、**別のvenvを作って**dbt-core 1.9系+dbt-osmosisを入れるのが安全

## 課題5: 月次の国別KPI

**出力**: 月 × 国(国内/US/その他海外)で、MAU・売上・課金UU・ARPPU・課金額の第1〜3四分位数。

**ヒント**
- **国情報はリポジトリに無い** → データレイクの `users` テーブル(`country`)をstg__usersとして追加して紐付ける(まさに「無い情報はデータレイクから」の課題)
- 国の3分類: `case when country = 'Japan' then '国内' when country = 'United States' then 'US' else 'その他海外' end`(countryの実値は要調査 — `dbt show --inline "select country, count(*) ... group by 1"`)
- グレインは月×国。材料の粒度は**ユーザー×月**(万能レシピどおり: ユーザー×月で「その月のアクセス有無・課金額」を確定 → 国を付与 → 月×国でGROUP BY)
- MAU = 月次アクセスUU(int__monthly_registered_user_typesのユーザー数がそのまま使える)
- 四分位数は「課金者のユーザー月次課金額」の分布に対して。`approx_quantiles(monthly_sales, 4)[offset(1)]`(第1)、`[offset(2)]`(中央値)、`[offset(3)]`(第3)がGROUP BY内で使えて楽。`percentile_cont` はウィンドウ関数なので集計には不向き
- Looker Studio: 表+期間コントロール+国のプルダウン

## 課題6: 新規ユーザーが登録月に最初に購入した商材別売上

**出力**: 月 × 商材名で、売上・新規UU。

**ヒント**
- 「登録」の定義を確認: `users.created_at`(ユーザー登録日)を使うのが素直(アクセスベースの「新規」とは別概念になり得る)
- 「最初に購入した」= ユーザーごとに購入明細を時刻順に並べて1件目 → `row_number() over (partition by user_id order by order_time_jst) = 1`。BigQueryなら `qualify` 句でWHEREいらずに絞れる
- 「登録月に」= 初回購入の月 = 登録月、のフィルタ
- 「商材名」がproduct_category(分類)かproduct_name(商品名)かは要確認。粒度的にはcategoryが現実的
- 新規UU = その月×商材で初回購入したユーザー数(distinct)

## 課題7: 離脱ユーザーが離脱月に最後に購入した商材別売上

**出力**: 月 × 商材名で、売上・離脱UU。離脱=最後のアクセスから14日以上アクセスしていないユーザー。

**ヒント**
- 離脱判定はユーザーごとの**最終アクセス日**(int__daily_registered_user_typesのmax(date))。「最終アクセス日+14日 < 基準日」なら離脱、離脱月=最終アクセス月
- **データ末尾のバイアスに注意**: 直近14日以内が最終アクセスのユーザーは離脱判定不能(まだ戻ってくるかもしれない)。データの最大日付から14日以内のユーザーは判定保留として除外する
- 「最後に購入した」= 課題6の逆順: `row_number() over (partition by user_id order by order_time_jst desc) = 1`
- 購入経験のない離脱ユーザーは「最後に購入した商材」が存在しない → 集計対象外になる(LEFT/INNERの選択を意識)

## 課題8: 2025年10月の課金セグメント×詳細ユーザータイプのピボット

**ヒント**
- **月次の詳細ユーザータイプを新たに作る必要がある**(資料にも明記)。int__monthly_registered_user_typesのuser_type × 「その月時点の課金経験フラグ」で5分類する
  - 月次の課金経験 = 「その月より前に購入したことがあるか」(int__daily_user_salesのpast_all_salesの月初スナップショット、または注文履歴から直接判定)
  - 月次の課金セグメントも同様に「どの時点の30日間か」の定義を決める必要がある(月初時点=前月の購入額、が自然)
- ピボット化はLooker Studioのピボットテーブルが楽。SQLでやるならBigQueryの `PIVOT` 演算子か、`countif(segment='a_...')` を列に並べる手書きピボット
- 2025年10月に絞るのは最後のWHERE(グレイン設計はいつもどおり全期間で作り、抽出はクエリ側)

## 課題9: 365日LTV

**出力**: 登録月 × (新規UU・365日売上・365日LTV)。

**ヒント**
- コホート分析の基本形。ユーザーごとに「登録日から365日以内の購入額合計」を出し(`date_diff(order_date, 登録日, day) < 365` で明細を絞って集計)、登録月でまとめる
- LTV = 365日売上合計 ÷ 新規UU(購入0円のユーザーも分母に含む点に注意 — 「平均を取る」の分母は登録者全員)
- **観測期間が足りないコホートを除外**: 登録から365日経過していない登録月は365日売上が未確定(構造的に過少)。`登録月 <= データ最大日付 - 365日` のコホートだけ出すか、注記を付ける(アクセスフラグの末尾バイアスと同じ論点)

## 課題10: ユーザー分析テーブル

**出力(1行=ユーザー)**: ユーザーID / 性別 / 国 / 登録日 / 2025-11-01時点の累計課金額 / 注文回数 / 最も購入金額の高いブランド名 / そのブランドへの2025-11-01時点の累計課金額 / 2025年10月のログイン日数。

**ヒント**
- 型としては「付与型」モデル(グレイン=ユーザー、GROUP BYで潰すのではなくユーザーに属性を集めていく)
- 性別・国・登録日 → データレイクの `users`(gender, country, created_at)
- 「2025-11-01時点」= `where date(order_time_jst) < '2025-11-01'` の時点指定を課金額系に適用
- 最も購入金額の高いブランド → ユーザー×ブランドで売上集計 → `row_number() over (partition by user_id order by brand_sales desc) = 1`(同率タイの扱いを決めておく)。`qualify` 句が便利
- 2025年10月のログイン日数 → eventsから `count(distinct アクセス日)`(user_id IS NULLは除外、期間は10月)
- 材料ごとにCTEを分け(ユーザー基本情報 / 課金集計 / トップブランド / ログイン日数)、最後にuser_idでLEFT JOINして組み立てる。usersに居るが購入・アクセスが無いユーザーの扱い(0埋めかNULLか)を決めること

---

## 全体を通じたヒント

- 分析系課題(5〜10)はすべて**万能レシピ**(aggregation-model-recipe.md)がそのまま使える。着手前に「出力グレイン / 数える単位 / 材料の粒度 / 揃え方 / 集計」の5行コメントを書くこと
- 新しい依存(users テーブル)は `_thelook__sources.yml` への登録+stg__usersの作成から(stg__events追加時と同じ手順)
- 「時点」や「期間」の定義(登録月・離脱・365日・2025-11-01時点)が各課題の急所。境界(以上/超え、含む/含まない)を実データで検算する癖を維持する
- データ特性の既知事項: events/ordersの日時非整合(売上捕捉率の問題)は、アクセス基準と購入基準を混ぜる課題(7・8など)で再び効いてくる可能性がある。数字が直感に反したら、まず上流との突き合わせで消失率を定量化する
