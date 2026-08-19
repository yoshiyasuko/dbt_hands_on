-- 参照モデル定義
with events as (
    select * from {{ ref("stg__events") }}
),
-- ユーザーID毎のアクセス日を集める
daily_access as (
    select distinct
        user_id,
        date(datetime(created_at, "Asia/Tokyo")) as date
    from events
    where user_id is not null
),
-- ユーザーID毎の前回・次回アクセス日を付与する
with_prev_and_next_access_date as (
    select
        user_id,
        date,
        lag(date) over user_daily as prev_date,
        lead(date) over user_daily as next_date
    from daily_access
    window user_daily as (
        partition by user_id
        order by date
    )
)

-- ユーザーID毎のアクセス日と前回・次回アクセス日をもとに、ユーザータイプ・アクセスフラグを分類する（アクセスフラグは累積型）
select
    user_id,
    date,
    case
        when prev_date is null then '新規'
        when date_diff(date, prev_date, day) > 14 then '復帰'
        else '既存'
    end as user_type,
    if(date_diff(next_date, date, day) = 1, 1, 0) as d1_access_flg,
    if(date_diff(next_date, date, day) between 1 and 3, 1, 0) as d1_3_access_flg,
    if(date_diff(next_date, date, day) between 1 and 7, 1, 0) as d1_7_access_flg,
    if(date_diff(next_date, date, day) between 1 and 14, 1, 0) as d1_14_access_flg
from with_prev_and_next_access_date
