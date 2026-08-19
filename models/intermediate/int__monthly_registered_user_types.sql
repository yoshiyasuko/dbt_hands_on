-- 参照モデル定義
with daily_registered_users as (
    select * from {{ ref("int__daily_registered_user_types") }}
)

-- 各月毎にグルーピングし、ユーザータイプを選定する
select
    date_trunc(date, month) as month,
    user_id,
    case
        when countif(user_type = '新規') > 0 then '新規'
        when countif(user_type = '復帰') > 0 then '復帰'
        else '既存'
    end as user_type
from daily_registered_users
group by month, user_id
