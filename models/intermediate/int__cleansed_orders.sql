{{ config(
    materialized="table",
    partition_by={
        "field": "order_time_jst",
        "data_type": "datetime",
        "granularity": "day"
    }, 
    cluster_by="user_id"
) }}

-- 参照モデル定義
with orders as (
    select * from {{ ref("stg__orders") }}
),
order_items as (
    select * from {{ ref("stg__order_items") }}
),
products as (
    select * from {{ ref("stg__products") }}
)

-- 注文データのクレンジング処理を行い、分析用の中間モデルを作成する
select 
    orders.order_id,
    orders.user_id,
    datetime(orders.created_at, "Asia/Tokyo") as order_time_jst,
    order_items.product_id,
    order_items.inventory_item_id,
    cast(round(order_items.sale_price * 150) as int) as sales_jpy,
    products.category as product_category,
    products.name as product_name,
    products.brand as product_brand,
    products.department as product_department
from orders
join order_items
using (order_id)
join products
on order_items.product_id = products.id
where orders.status not in ('Cancelled', 'Returned')
