select 
    status,
    count(*) as counts
from {{ ref("stg__order_items") }}
group by status
order by counts desc
