{% snapshot users_extract_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='id',
        strategy='check',
        check_cols='all'
    )
}}

select
    id,
    postcode
from {{ source('operational', 'users_extract') }}

{% endsnapshot %}