# Meet the Stack You're On Call For

You run **The Reef Shop** - a three-service store (frontend, orders, payments) on Kubernetes. Prometheus watches it, every service streams JSON logs to disk, and support exports tickets to a columnar file. Four systems, and four different ways to ask them questions: `kubectl`, PromQL, `grep`-and-`jq`, and a columnar-file reader. That sprawl is exactly what **Coral** collapses into one SQL connection - but first, feel the sprawl.

You just joined the SRE rotation for The Reef Shop. Before any incident hits, an SRE learns the terrain: what runs where, what watches it, and where the data lives. In this challenge you'll survey all of it - and count how many different tools that survey takes.

> Nothing is broken yet. Enjoy it while it lasts.

---

## Step 1: Browse the store

This is what your customers see. Open the **Shop** tab - it exercises the full request path: frontend -> orders -> payments.

Pick a coral and click **Buy now**. A small confirmation message pops up in the top-right corner, the order lands in the **Recent orders** feed, and the status bar along the bottom shows all three services green - the whole chain is healthy.

---

## Step 2: List the workloads

Now the operator view. Head to the **Terminal** and ask Kubernetes what's running.

```bash,run
kubectl get pods -o wide
```

Three shop services plus Prometheus, all `Running`. This is tool number one: `kubectl`, speaking Kubernetes API.

---

## Step 3: Check the monitoring

Prometheus scrapes every service and evaluates alert rules. Open the **Prometheus** tab and go to its Alerts page (`/alerts`).

Both rules - `PaymentsHighErrorRate` and `ShopTargetDown` - should be green (inactive). This is tool number two: PromQL and the Prometheus UI.

---

## Step 4: Inspect the raw data

Logs and tickets don't live in either of those tools. Back in the **Terminal**, look at the files directly.

```bash,run
ls -lh /root/data/
```

Then peek at the last few log lines:

```bash,run
tail -3 /root/data/logs.jsonl
```

Two files: JSON log lines harvested from the pods every 30 seconds, and a support-ticket export sitting next to them. Tools three and four: raw JSON you'd normally attack with `grep` and `jq`, and a columnar ticket file that needs its own reader entirely.

> **Note:** Four systems, four interfaces - and during a real incident you'd be juggling all of them at once. Keep that number in mind; the next challenge replaces it with one.

---

<instruqt-task id="meet_the_stack"></instruqt-task>

You know the terrain. Move on to **Challenge 2** to give this stack one SQL connection.
