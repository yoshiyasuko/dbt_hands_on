---
name: update-model-catalog
description: dbtモデルの変更内容を分析し、モデルカタログ(notes/model-catalog.md)の更新が必要かを判断・更新する。モデルの追加・削除、カラムの追加・削除・型変更、マテリアライズ・パーティション設定の変更があった場合や、コミット前のフックとして使用する。変更がなくてもカタログの記述が実態と乖離していないか検証する機能も持つ。
---

# update-model-catalog

dbtモデルの変更内容を分析し、`notes/model-catalog.md`(全モデルのカラム・内容・型カタログ)の更新が必要かを判断・更新する。モデル定義とカタログの乖離を防ぐため、コミット前に呼び出す。

また、変更がなくてもカタログの記述が実態と乖離していないか検証する機能も持つ。定期的に呼び出して、カタログの正確性を保つ。

## 手順

### 1. 動作モードの決定

以下を並列で実行して、モデル関連の未コミット変更があるかを確認する：
- `git diff HEAD -- models/ macros/ dbt_project.yml` — 未コミットの変更
- `git diff --cached -- models/ macros/ dbt_project.yml` — ステージ済みの変更
- `git status --short models/` — 未追跡の新規モデルファイル
- `git log --oneline -5` — 直近コミット（最近の変更の流れを把握するため）

**モデル関連の変更がある場合** → **差分モード**（ステップ2へ）
**変更がない場合** → **検証モード**（ステップ4へ）

`notes/model-catalog.md` が存在しない場合は、検証モードの手順に沿って全モデル分を新規作成する。

---

## 差分モード（モデル変更に伴うカタログ更新）

### 2. 差分ベースの更新判断

Read ツールで `notes/model-catalog.md` と変更されたモデルのSQL・YAMLを読み込み、カタログへの影響を判定する。

**更新が必要：**
- モデルの追加・削除・リネーム（該当セクションと冒頭の依存関係図・モデル数の更新）
- カラムの追加・削除・リネーム・型の変更（カラム表の更新）
- グレイン・JOIN方式・フィルタ条件の変更（モデル概要文への影響）
- `materialized` / `partition_by` / `cluster_by` 等の設定変更（設定の記述への影響）
- 分類カラムの取り得る値の変更（user_type・課金セグメント等。カタログは値の台帳を兼ねる）
- `ref()` の追加・削除（依存関係図への影響）
- YAMLのdescription変更（「内容」列への影響）

**更新不要と判断してよいケース：**
- 出力カラム・型・グレインが変わらないロジック内部の修正（計算式の等価な書き換え、CTE名の変更等）
- コメント・整形のみの変更
- data_testsの追加・変更のみ（カタログに記載しているaccepted_valuesの値が変わる場合を除く）

→ ステップ3（型の確定）へ

### 3. 型の確定

カラム表の「型」列は**BigQuery上の実際の型を正**とする。変更されたモデルについて以下で確認する：

```bash
venv/bin/dbt show --inline "select column_name, data_type from \`data-promotion-sandbox\`.dbt_ko_hands_on.INFORMATION_SCHEMA.COLUMNS where table_name = '<物理名>' order by ordinal_position" --limit 100
```

- 物理名は `generate_alias_name` によるprefix除去後の名前（例: `int__cleansed_orders` → `cleansed_orders`）。staging層は `stg__` のまま
- INFORMATION_SCHEMAのカラム構成が変更後のSQLと一致しない場合（変更後にまだ `dbt run` されていない）は、SQL・YAMLの `data_type` から型を推定し、該当カラムの「型」列に `(推定)` と注記する。このスキルから `dbt run` は実行しない（実行要否は呼び出し元・ユーザーに委ねる）
- カタログ冒頭に記載している型の取得日を、INFORMATION_SCHEMAで確認した日付に更新する

→ ステップ5（更新案の提示と確認）へ

---

## 検証モード（カタログと実態の整合性チェック）

### 4. カタログとモデルの突き合わせ

以下を並列で読み込み、カタログの記述と実態を照合する：
- `notes/model-catalog.md`
- `models/` 配下の全SQL・YAML
- BigQueryの型情報（全モデル一括）:

```bash
venv/bin/dbt show --inline "select table_name, ordinal_position, column_name, data_type from \`data-promotion-sandbox\`.dbt_ko_hands_on.INFORMATION_SCHEMA.COLUMNS order by table_name, ordinal_position" --limit 300
```

**チェックリスト：**

| チェック対象 | 照合先 | 確認内容 |
|---|---|---|
| モデルの過不足 | `models/` 配下のSQLファイル | カタログに全モデルのセクションがあるか、削除済みモデルが残っていないか |
| カラムの過不足・順序 | 各モデルのSELECT句・INFORMATION_SCHEMA | カラム表が実際の出力と一致するか |
| 型 | INFORMATION_SCHEMA | 「型」列が実測値と一致するか |
| グレイン・設定の記述 | SQLの `config()`・GROUP BY・JOIN | パーティション・クラスタリング・グレインの説明が実態と一致するか |
| 依存関係図 | 各SQLの `ref()` / `source()` | 図が実際の依存と一致するか |
| 分類カラムの値 | SQLのCASE式・YAMLのaccepted_values | 記載している取り得る値が一致するか |
| 補足セクション | 実測の型 | 型の注意点（sales型の不統一等）が現状と一致するか |

不整合が見つからない場合は「model-catalog.md の記述は実態と整合しています」と伝えて終了。

→ ステップ5（更新案の提示と確認）へ

---

## 共通ステップ

### 5. 更新案の提示と確認

更新が必要と判断した場合、AskUserQuestion ツールで更新内容を提示し確認を取る：

- 質問文に、どのモデルのどの箇所をどう変更するかを具体的に記載する
- 選択肢: ["更新する", "スキップ"]

更新が不要と判断した場合は理由を伝えて終了。

### 6. 更新の実行

ユーザーが「更新する」を選んだ場合のみ、Edit ツールで該当箇所を更新する。

- 既存のフォーマットを維持する（層ごとのセクション構造、「カラム / 型 / 内容」の3列テーブル、冒頭の依存関係図と型取得日、末尾の補足セクション）
- 変更に関係する箇所だけを編集する（全体の書き換えはしない）
- 推測で書かない。SQLとBigQueryから読み取れる事実のみを記述し、推定の型には `(推定)` を付ける

### 7. 結果の報告

更新した場合は、変更箇所を簡潔に報告する。`/git-workflow:commit` 等の他スキルから呼ばれている場合は報告後に制御を返す（更新したカタログはコミット対象に含める）。
