{{
    config(
        materialized="incremental",
        incremental_strategy="insert_overwrite",
        partition_by={
            "field": "date",
            "data_type": "date",
        }
    )
}}

select 
    date(order_time_jst) as date,
    sum(sales_jpy) as sales,
    count(distinct user_id) as payment_uu,
    round(safe_divide(sum(sales_jpy), count(distinct user_id)), 1) as arppu
from {{ ref("int__cleansed_orders") }} as cleansed_orders
{% if is_incremental() %}
where date(order_time_jst) >= date_sub(current_date("Asia/Tokyo"), interval 6 day)
{% endif %}
group by date
