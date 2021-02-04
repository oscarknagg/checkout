{{
    config(
        materialized='incremental',
        unique_key='_id',
        sort='hour'
    )
}}

with filtered_pageviews as (

    select *
    from {{ ref('user_pageviews_by_hour') }} pageviews

    {% if is_incremental() %}

    where pageviews."hour" >= (select COALESCE(max("hour"), timestamp 'epoch') from {{ this }} )

    {% endif %}
),

postcode_updates_before_pageviews as (

    select
        pageviews."hour",
        pageviews.user_id,
        users.postcode,
        pageviews.num_pageviews,
        datediff(second, dbt_valid_from, pageviews."hour") as seconds_from_update_to_view,
        row_number() over (
            partition by pageviews.user_id, pageviews."hour"
            order by seconds_from_update_to_view
        ) as update_recency_rank
    from filtered_pageviews pageviews
    left join {{ ref('users_extract_snapshot')}} users
        on pageviews.user_id = users.id
    where
        seconds_from_update_to_view > 0 -- Only want updates from before the event

),

most_recent_postcode_update_before_pageviews as (

    select
        "hour",
        user_id,
        postcode,
        num_pageviews
    from postcode_updates_before_pageviews
    where
        update_recency_rank = 1

),

pageviews_by_postcode as (
    select
        "hour",
        postcode,
        sum(num_pageviews) as num_pageviews
    from most_recent_postcode_update_before_pageviews
    group by
        "hour",
        postcode
    )

select
    {{ dbt_utils.surrogate_key(['hour', 'postcode']) }} as _id,
    "hour",
    postcode,
    num_pageviews
from pageviews_by_postcode