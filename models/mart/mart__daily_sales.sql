select 
    date(order_time_jst) as date,
    sum(sales_jpy) as sales,
    count(distinct user_id) as payment_uu,
    round(safe_divide(sum(sales_jpy), count(distinct user_id)), 1) as arppu
from {{ ref("int__cleansed_orders") }} as cleansed_orders
group by date
order by date
