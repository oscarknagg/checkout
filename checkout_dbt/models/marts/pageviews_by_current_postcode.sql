{{
    config(
        materialized='table'
    )
}}

select
    pageviews."hour",
    users.postcode, -- current postcode
    sum(num_pageviews) as num_pageviews
from {{ ref('user_pageviews_by_hour') }} pageviews
inner join {{ source('operational', 'users_extract')}} users
    on pageviews.user_id = users.id
group by
    pageviews."hour",
    users.postcode
