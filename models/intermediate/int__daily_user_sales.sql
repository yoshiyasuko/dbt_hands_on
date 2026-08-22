-- 参照モデル定義
with daily_registered_user_types as (
    select * from {{ ref("int__daily_registered_user_types") }}
),
cleansed_orders as (
    select * from {{ ref("int__cleansed_orders") }}
),
-- 売上を集計する（グレイン: ユーザーID・日付）
sum_order_sales as (
    select
        daily_registered_user_types.user_id as user_id,
        daily_registered_user_types.date as date,
        -- 売上
        cast(coalesce(sum(cleansed_orders.sales_jpy), 0) as float64) as sales
    from daily_registered_user_types
    left join cleansed_orders
        on daily_registered_user_types.user_id = cleansed_orders.user_id
        and daily_registered_user_types.date = date(cleansed_orders.order_time_jst)
    group by user_id, date
),
-- 過去30日間売上・過去累計売上を確定する
with_past_sales as (
    select
        user_id,
        date,
        sales,
        -- 過去30日間売上
        coalesce(sum(sales) over (
            partition by user_id
            order by unix_date(date)    -- 日付を「エポック日からの経過日数」に変換することで、日付をrange指定できるようにする
            range between 30 preceding and 1 preceding
        ), 0) as past_d30_sales,
        -- 過去累計売上
        coalesce(sum(sales) over (
            partition by user_id
            order by unix_date(date)    -- 日付を「エポック日からの経過日数」に変換することで、日付をrange指定できるようにする
            range between unbounded preceding and 1 preceding
        ), 0) as past_all_sales
    from sum_order_sales
)

-- 過去30日間購入金額セグメント・購入経験フラグを集計し、テーブルを確定する
select
    user_id,
    date,
    sales,
    past_d30_sales,
    past_all_sales,
    case
        when past_d30_sales >= 50001 then 'a_50,001円~'
        when past_d30_sales >= 30001 then 'b_30,001円~50,000円'
        when past_d30_sales >= 10001 then 'c_10,001円~30,000円'
        when past_d30_sales >= 5001 then 'd_5,001円~10,000円'
        when past_d30_sales >= 3001 then 'e_3,001円~5,000円'
        when past_d30_sales >= 1001 then 'f_1,001円~3,000円'
        when past_d30_sales >= 1 then 'g_1円~1,000円'
        else 'h_0円'
    end as past_d30_payment_segment,
    if(past_all_sales > 0, 1, 0) as payment_experience_flg
from with_past_sales
