select * from {{ source('thelook_ecommerce', 'order_items') }}
