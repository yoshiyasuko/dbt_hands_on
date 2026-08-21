-- 参照モデル定義
with cleansed_orders as (
    select * from {{ ref("int__cleansed_orders") }}
),
monthly_registered_user_types as (
    select * from {{ ref("int__monthly_registered_user_types") }}
),

-- 注文明細に月とユーザータイプを付与
orders_with_month_and_user_type as (
    select
        date_trunc(date(cleansed_orders.order_time_jst), month) as month,
        monthly_registered_user_types.user_type,
        cleansed_orders.product_department as department,
        cleansed_orders.product_brand as brand,
        cleansed_orders.user_id,
        cleansed_orders.sales_jpy
    from cleansed_orders
    join monthly_registered_user_types
    on cleansed_orders.user_id = monthly_registered_user_types.user_id and date_trunc(date(cleansed_orders.order_time_jst), month) = monthly_registered_user_types.month
),

-- ブランド「その他」判定用に「月・部門・ブランド」のUUを集計
brand_uu as (
    select
        month,
        department,
        brand,
        count(distinct user_id) as uu
    from orders_with_month_and_user_type
    group by month, department, brand
),

-- ブランド「その他」の反映した注文明細に置き換え
relabeled_orders as (
    select
        orders_with_month_and_user_type.month,
        orders_with_month_and_user_type.user_type,
        orders_with_month_and_user_type.department,
        if(brand_uu.uu < 10, 'その他', orders_with_month_and_user_type.brand) as brand,
        orders_with_month_and_user_type.user_id,
        orders_with_month_and_user_type.sales_jpy
    from orders_with_month_and_user_type
    left join brand_uu
    using (month, department, brand)
)

-- 月・部門・ブランド・ユーザータイプ別に売上・購入UUを集計
select
    month,
    user_type,
    department,
    brand,
    cast(sum(sales_jpy) as float64) as sales,
    count(distinct user_id) as payment_uu
from relabeled_orders
group by month, department, brand, user_type
