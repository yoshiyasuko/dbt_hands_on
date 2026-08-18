{{ config(
    materialized="table",
    partition_by={
        "field": "order_time_jst",
        "data_type": "datetime",
        "granularity": "day"
    }, 
    cluster_by="user_id"
) }}

select 
    orders.order_id,
    orders.user_id,
    datetime(orders.created_at, "Asia/Tokyo") as order_time_jst,
    order_items.product_id,
    order_items.inventory_item_id,
    cast(round(order_items.sale_price * 150) as int) as sales_jpy
from {{ ref("stg__orders") }} as orders
join {{ ref("stg__order_items") }} as order_items
using (order_id)
where orders.status not in ('Cancelled', 'Returned')
