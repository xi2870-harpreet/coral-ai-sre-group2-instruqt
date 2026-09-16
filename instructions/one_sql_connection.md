# One SQL Connection

In the last challenge you touched four different tools. Now meet the layer that makes them one. Coral is connected to your cluster, your Prometheus, and your data files - everything you toured is about to become SQL tables under a single connection.

Coral is already installed and connected to three sources: `k8s` (your cluster, read via the Kubernetes API), `prometheus` (alerts and scrape health), and `shopdata` (the JSONL logs and the ticket export). Each source's data appears as ordinary SQL tables - and tables from *different* sources JOIN like they live in one database.

> Start every investigation with: `SELECT schema_name, table_name FROM coral.tables`

---

## Step 1: See what's connected

List Coral's sources. Each one was added from a small YAML spec - no code, no plugins.

```bash,run
coral source list
```

You should see three sources: `k8s`, `prometheus`, and `shopdata`.

---

## Step 2: Discover the catalog

Every Coral workspace has a built-in catalog. This is the query to start any investigation with - it tells you every table you can reach.

```bash,run
coral sql "SELECT schema_name, table_name FROM coral.tables"
```

Pods, deployments, events, alerts, logs, tickets - one catalog, three very different systems behind it. Everything listed here is now queryable with plain SQL.

---

## Step 3: Query each world

Prove each source speaks SQL. Kubernetes first:

```bash,run
coral sql "SELECT name, status, node_name FROM k8s.pods WHERE namespace = 'default'"
```

Four rows - your three shop services plus Prometheus, all `Running`. That's a live Kubernetes API call wearing a SQL costume. Then the log file - same syntax, no `jq` in sight:

```bash,run
coral sql "SELECT ts, service, level, message FROM shopdata.logs ORDER BY ts DESC LIMIT 5"
```

The same JSON lines you tailed in challenge 1, now sorted and filtered by a query engine. And the ticket export:

```bash,run
coral sql "SELECT ticket_id, service, priority, subject FROM shopdata.tickets WHERE status = 'open'"
```

Four open tickets - and notice that three of them already point at **payments**. File that away; it becomes relevant sooner than you'd like.

---

## Step 4: The first cross-source JOIN

Here's the moment that separates Coral from a pile of connectors: JOIN live cluster state against the log file - one query, two systems.

```bash,run
coral sql "SELECT p.name AS pod, p.status, COUNT(l.request_id) AS log_lines FROM k8s.pods p LEFT JOIN shopdata.logs l ON l.pod = p.name WHERE p.namespace = 'default' GROUP BY p.name, p.status ORDER BY log_lines DESC" | tee /root/answers/first-join.txt
```

We save the output to `/root/answers/first-join.txt` - it's your evidence, and the Check button grades it. Every row pairs a *live* Kubernetes pod with how many log lines it has shipped to disk. No API pagination, no glue script - the JOIN happened inside Coral's engine.

---

## Step 5: See it in the Coral UI

Coral also ships a local UI. Open the **Coral UI** tab and look at the **Traces** view - it's a live query stream: every SQL statement you just ran, with execution timings. This is your query audit trail, and it matters more than it looks: when an *agent* is doing the querying, this stream is how you see exactly what it asked and how long each answer took.

Then look at the raw files behind `shopdata` from the **Terminal**:

```bash,run
cat /root/data/logs.jsonl | head -5
```

Those are the exact lines your Step 3 query returned, one JSON object per line - readable, but imagine grepping a gigabyte of it. Now try the ticket export:

```bash,run
file /root/data/tickets.parquet
```

It isn't empty - it's columnar binary, and your four open tickets live inside it. A text editor shows nothing useful here. That contrast is the lesson: one source has files a human can read but not query, the other has files SQL can query but a human can't read - and Coral gave both the same interface.

> **Warning:** Look, don't edit - these files are live data. The graders (and challenge 4's incident investigation) query them.

> **Note (finding):** The original track viewed these files in a dedicated "Data Files" code-editor tab (`/root/data`). Labs 2.0's `editor` resource only supports a `container` target, not `vm` - since this whole sandbox is one VM, there's no equivalent tab here. Ported as a deviation: file inspection moved to the Terminal (`cat`, `file`) instead.

---

<instruqt-task id="one_sql_connection"></instruqt-task>

Three systems, one connection, and your first cross-source JOIN. Move on to **Challenge 3** to hand this power to an agent.
