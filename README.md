# dbt/SQL pipeline

I have chosen to implement the SQL pipeline part of the test using `dbt`.
The `dbt` code I have written assumes we are using a Redshift cluster as the data warehouse but the 
code should be relatively easy to transfer to Snowflake.

## Choice of data warehouse

I have chosen Redshift as it is well supported and integrates well with AWS. This unlocks easy integrations 
e.g. AWS Firehose lets you easily load data into Redshift in near real-time from Kinesis streams.
A downside of Redshift compared to Snowflake is that compute and storage is more tightly coupled.
This can be remediated by using [RA3 nodes](https://aws.amazon.com/about-aws/whats-new/2019/12/amazon-redshift-announces-ra3-nodes-managed-storage/) 
which separate compute and storage scaling. 
Unfortunately these start at about 40x the cost of the basic node type which means this option may not be 
cost-efficient for modestly sized data warehouses.

Personally, the method I've used to remediate the storage/compute coupling of Redshift is 
[AWS Spectrum](https://docs.aws.amazon.com/redshift/latest/dg/c-getting-started-using-spectrum.html) which lets you
query data stored in files on S3 using SQL running on a Redshift cluster.
The best data to offload to Spectrum is ultra-high volume (and quickly growing) data like pageviews, clicks and 
behavioural events.
This is because Spectrum queries cost proportional to the amount of data scanned and although this kind of data is huge, 
time-based partitioning means that only relatively modest amounts are actually scanned. 



## Data warehouse schemas and tables

First I will create a `raw_data` schema that extract/load tasks will interact with. 
The reason to use a separate schema is twofold:
1. Its clear that all tables in this schema will be source tables in dbt
2. This schema can have separate permissions such that analyst users cannot interact with this schema (only through 
   derived models)

```
CREATE SCHEMA raw_data;
```

Secondly, I will create a table for `users_extract` and `pageviews_extract` within this schema.
The `distkey` keyword in Redshift indicates that the data will be partitioned across nodes using this key.
The `sortkey` keyword indicates which column is used to sort data within each node.

I have chosen both tables to be distributed on user IDs. 
In Redshift this leads to increased join performance as records with the same value of the user ID column will be
co-located on the same node.

The sortkey of `pageviews_extract` is the timestamp column as I expect that users will be much more interested in 
recent data than old data and so the timestamp column will be used most frequently in WHERE clauses.
In Redshift the sortkey has a profound impact on filtering performance as it lets more data blocks (roughly equivalent
to micro-partitions in Snowflake) be skipped during table scans. 
Timestamp is also a good choice as it is high cardinality, if I chose a boolean column then I could only skip 50% of 
data blocks at best (with a 50/50 distribution of values) whereas with timestamp I expect >90% 
of data blocks will be skipped.

A similar logic applies to `sortkey(id)` on `users_extract` although I expect a lesser performance gain because
old users will still remain business-relevant if they are still active.
```
CREATE TABLE raw_data.users_extract (
	id integer,
	postcode varchar(16)
)
distkey(id)
sortkey(id);

CREATE TABLE raw_data.pageviews_extract (
	user_id integer,
	"timestamp" timestamp,
	url varchar(max)
)
distkey(user_id)
sortkey("timestamp");
```

## Transform pipeline

### Scheduling the transform pipeline

The tool I would use to schedule the pipeline is Airflow as it can flexibly define ETL workflows as code and lets you 
configure things like retries, timeouts and of course the DAG structure as you please.

I won't implement an Airflow DAG for this test but I will offer some Airflow "pseudocode" to suggest what I think
would be an appropriate DAG structure.

DAG 1: Daily ETL
```
# Cron schedule: 0 0 * * * (daily at midnight)

# Define Operators

users_extract = Operator("Performs full load of users data")
pageviews_extract = Operator("Incremental load of pageviews data")
dbt_deps = Operator("dbt deps")
dbt_snpashot = Operator("dbt snapshot")
dbt_run = Operator("dbt run")
dbt_test = Operator("dbt test")

# Define DAG

[users_extract, pageviews_extract] >> dbt_deps
dbt_deps >> dbt_snpashot >> dbt_run >> dbt_test

```

DAG 2: Hourly update
```
# Cron schedule: 0 1-23 * * * (hourly except midnight)
pageviews_extract = Operator("Incremental load of pageviews data")
dbt_partial_run = Operator("dbt run -m source:operational.pageviews_extract")

pageviews_extract >> dbt_partial_run
```

DAG 1 is our "main" ETL that waits for extract tasks to finish before taking a dbt snapshot (of users_extract) and 
doing a full run. 

DAG 2 is a secondary ETL process that updates just the models downstream of the pageviews_extract when it is completed.
In this case this is all of the models but in practice its likely to be just a subset.


#### Extra fun: Autogenerating DAG structure

The problem with DAG 1 is that it treats the `dbt run` step as a single operation.
If you have, say, export tasks that send transformed data to a 3rd party these will wait until dbt run is completely
finished when in fact they may depend on just one dbt model.
The same goes for tasks that might refresh dashboards in BI tools.

You can split up the `dbt run` operator into a full dag using the `manifest.json` produced after any dbt operation as 
this file contains the DAG of your dbt project.
In particular, the `parent_map` key contains the DAG structure
With a bit of configuration such as registering what downstream tasks depend on which models you can auto-generate
```
import networkx as nx
dbt_dag_structure: nx.Digraph = parse_dbt_dag('/path/to/manifest.json')

for parent, child in dbt_dag_structure.edges():
    parent >> child

# Add a dashboard refresh task that depends only on one model
dbt_dag_structure.node['pageviews_by_postcode'] >> Operator("refresh pageviews dashboard")
```

## Running the pipeline

1. Install dbt in a python virtual env following the [dbt docs](https://docs.getdbt.com/dbt-cli/installation/)
3. Spin up a Redshift cluster and load in some data into `raw_data.pageviews_extract` and `raw_data.users_extract`
4. Add your Redshift connection details as environment variables (see `checkout_dbt/profiles_template.yml`) 
5. Copy and rename `cp checkout_dbt/profiles_template.yml ~/.dbt/profiles.yml`
6. Run `cd /path/to/this_repo/checkout_dbt` and `dbt deps && dbt run`