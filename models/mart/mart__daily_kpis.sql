-- 出力グレイン
    -- 日付×詳細ユーザータイプ×30日間課金セグメント
-- メジャーの数える単位
    -- ユーザー（dau・uu系）・円（sales系）
-- 材料の粒度
    -- 日付×ユーザー
-- 必要な材料
    -- int__daily_registered_user_types（ユーザータイプ・アクセスフラグ）
    -- int__daily_user_sales（ユーザーの売上）

-- 参照モデル定義
with daily_registered_user_types as (
    select * from {{ ref("int__daily_registered_user_types") }}
),
daily_user_sales as (
    select * from {{ ref("int__daily_user_sales") }}
),
-- 出力グレインに必要な属性である30日間課金セグメントと集計用の情報を揃える
user_days as (
    select
        user_types.date,
        user_types.user_id,
        case
            when user_type = '新規' then '新規'
            when user_type = '復帰' then
                case
                    when payment_experience_flg = 0 then '復帰無課金'
                    else '復帰課金経験'
                end
            when user_type = '既存' then
                case
                    when payment_experience_flg = 0 then '既存無課金'
                    else '既存課金経験'
                end
        end as detail_user_type,
        user_sales.past_d30_payment_segment,
        user_types.d1_access_flg,
        user_types.d1_3_access_flg,
        user_types.d1_7_access_flg,
        user_types.d1_14_access_flg,
        user_sales.sales
    from daily_registered_user_types as user_types
    left join daily_user_sales as user_sales
        on user_types.user_id = user_sales.user_id
        and user_types.date = user_sales.date
)

-- 出力グレインの日付×詳細ユーザータイプ×30日間課金セグメントをもとに、メジャーを集計する
select
    date,
    detail_user_type,
    past_d30_payment_segment,
    count(distinct user_id) as dau,
    countif(detail_user_type = '新規') as new_uu,
    sum(d1_access_flg) as d1_access_uu,
    sum(d1_3_access_flg) as d1_3_access_uu,
    sum(d1_7_access_flg) as d1_7_access_uu,
    sum(d1_14_access_flg) as d1_14_access_uu,
    count(distinct if(sales > 0, user_id, null)) as payment_uu,
    sum(sales) as sales
from user_days
group by date, detail_user_type, past_d30_payment_segment
