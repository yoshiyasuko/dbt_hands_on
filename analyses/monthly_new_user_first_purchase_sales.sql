-- 定義: 「最初に購入した商材」= 初回注文から決定的に選んだ明細1件(同時刻タイはorder_id→inventory_item_id順)。商材名はカテゴリ粒度を採用

-- 出力項目
    -- 月(month)
    -- 商材名(product_category)
    -- 売上(sales)
    -- 新規UU(new_user_uu)
-- ディメンション
    -- 月(month)
    -- 商材名(product_category)
-- メジャー
    -- 売上(sales)
    -- 新規UU(new_user_uu)
-- 材料の表（CTEで作るべきもの）
    -- ユーザーID(user_id)
    -- 月(month)
    -- 商材名(product_category)
    -- 売上(sales_jpy)
-- 出どころ
    -- ユーザーID(user_id)
    -- 商材名(product_category)
    -- 売上(sales_jpy)
        -- int__cleansed_ordersに存在。しかし、int__cleansed_ordersは全購入情報のため、初回の1件に絞る必要がある。
        -- どう作る？
    -- 登録月(month)
        -- stg__usersにcreated_atが存在。しかし、これはTIMESTAMPのため月単位に変換が必要。


-- 参照モデル定義
with cleansed_orders as (
    select * from {{ ref("int__cleansed_orders") }}
),
users as (
    select * from {{ ref("stg__users") }}
),

-- ユーザーの登録日を登録月に変更した表を作成
users_with_registered_month as (
    select
        id as user_id,
        date_trunc(date(created_at, "Asia/Tokyo"), month) as registered_month
    from users
),

-- ユーザー毎の初回の購入明細を取得
first_purchase_per_user as (
    select
        user_id,
        date_trunc(date(order_time_jst), month) as first_order_month,
        product_category,
        sales_jpy
    from cleansed_orders
    qualify row_number() over (
        partition by user_id
        order by order_time_jst, order_id, inventory_item_id
    ) = 1
),

-- 登録月に初回購入したユーザーの購入明細を取得
new_user_first_purchase as (
    select
        first_purchase_per_user.user_id,
        first_purchase_per_user.first_order_month as month,
        first_purchase_per_user.product_category as product_category,
        first_purchase_per_user.sales_jpy
    from first_purchase_per_user
    join users_with_registered_month
        using (user_id)
    where first_purchase_per_user.first_order_month = users_with_registered_month.registered_month
)

-- 月×商材名でグループ化し、売上と新規UUを集計
select
    month,
    product_category,
    sum(sales_jpy) as sales,
    count(distinct user_id) as new_user_uu
from new_user_first_purchase
group by month, product_category
