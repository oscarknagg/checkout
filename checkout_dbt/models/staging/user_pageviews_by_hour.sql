{{
    config(
        materialized='incremental',
        unique_key='_id',
        sort='hour',
        dist='user_id'
    )
}}


with hour_pageviews as (
    select
        date_trunc('hour', pageviews."timestamp") as _hour,
        user_id,
        count(*) as num_pageviews
    from {{ source('operational', 'pageviews_extract') }} pageviews

    {% if is_incremental() %}

    where pageviews."timestamp" >= (select COALESCE(max("hour"), timestamp 'epoch') from {{ this }} )

    {% endif %}

    group by
        _hour,
        user_id
)

select
    {{ dbt_utils.surrogate_key(['_hour', 'user_id']) }} as _id,
    _hour as "hour",
    user_id,
    num_pageviews
from hour_pageviews
