-- 出力グレイン
    -- 月×国
-- メジャーの数える単位
    -- ユーザー（mau・uu系）・円（sales系）
-- 材料の粒度
    -- 月×ユーザー
-- 必要な材料
    -- stg__users（ユーザーの国）
    -- int__daily_user_sales（ユーザーの売上）

{{
    config(
        materialized="incremental",
        incremental_strategy="insert_overwrite",
        partition_by={
            "field": "month",
            "data_type": "date",
            "granularity": "month"
        }
    )
}}

-- 参照モデル定義
with users as (
    select * from {{ ref("stg__users") }}
),
daily_user_sales as (
    select * from {{ ref("int__daily_user_sales") }}
    {% if is_incremental() %}
    where date >= date_trunc(date_sub(current_date("Asia/Tokyo"), interval 6 day), month)
    {% endif %}
),

-- 月×ユーザーで売上を集計
monthly_user_sales as (
    select
        date_trunc(date, month) as month,
        user_id,
        sum(sales) as sales
    from daily_user_sales
    group by month, user_id
),

-- 月×ユーザーに国を付与
monthly_user_sales_with_country as (
    select
        monthly_user_sales.month,
        monthly_user_sales.user_id,
        case
            when users.country is null then '不明'
            when users.country = 'Japan' then '国内'
            when users.country = 'United States' then 'US'
            else 'その他海外'
        end as country,
        monthly_user_sales.sales
    from monthly_user_sales
    join users
        on monthly_user_sales.user_id = users.id
),

-- 月×国に四分位数を付与
monthly_user_sales_with_country_and_quartile as (
    select
        *,
        percentile_cont(if(sales > 0, sales, null), 0.25) over sales_window as sales_q1,
        percentile_cont(if(sales > 0, sales, null), 0.5) over sales_window as sales_q2,
        percentile_cont(if(sales > 0, sales, null), 0.75) over sales_window as sales_q3
    from monthly_user_sales_with_country
    window sales_window as (
        partition by month, country
    )
)

-- 月×国で売上・購入UU・MAU・ARPPUを集計
select
    month,
    country,
    count(distinct user_id) as mau,
    sum(sales) as sales,
    count(distinct if(sales > 0, user_id, null)) as payment_uu,
    round(safe_divide(sum(sales), count(distinct if(sales > 0, user_id, null))), 1) as arppu,
    -- 四分位数はパーティションで全て同値のため、any_valueで1件だけ取得する
    any_value(sales_q1) as sales_q1,
    any_value(sales_q2) as sales_q2,
    any_value(sales_q3) as sales_q3
from monthly_user_sales_with_country_and_quartile
group by month, country
