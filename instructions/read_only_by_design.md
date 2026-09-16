# Read-Only by Design - and Extensible in One YAML File

The fire is out - setup rolled payments back to v1 while you weren't looking. What's left is the conversation every platform team has before adopting agent tooling: blast radius and reach. Both answers live in this challenge.

The incident is fixed - payments is back on v1. Two questions remain before anyone lets an agent near production: **can it break anything?** and **can it reach our own systems?** Coral's answers: structurally no, and yes - in one short YAML spec.

---

## Step 1: Try to break production

You have a connection that can see everything. Try to *change* something with it:

```bash,run
coral sql "DELETE FROM k8s.pods WHERE name LIKE 'payments%'" 2>&1 | tee /root/answers/mutation-attempt.txt
```

An error is exactly what you want here:

```
Error (invalid argument): invalid input: DML not supported: Delete
```

That's not a permission denying you - it's the query engine reporting it has no DELETE capability at all. We keep the refusal as `/root/answers/mutation-attempt.txt` - a receipt worth showing your security team.

And try an UPDATE for good measure:

```bash,run
coral sql "UPDATE shopdata.tickets SET status = 'closed'"
```

Same refusal, `DML not supported: Update`. Both fail - not because a permission said no, but because the engine has no write path to say yes with. That's the difference between *policy* and *architecture*. Hand this connection to any agent and the worst it can do is read.

---

## Step 2: Read a source spec

Everything Coral queried today came from small YAML specs. From the **Terminal**, open the one that powered your incident logs:

```bash,run
cat /root/specs/shopdata.yaml
```

Location, glob, columns - that's the whole integration. No SDK, no code.

---

## Step 3: Wrap your own API in one small spec

The shop's frontend exposes a stats endpoint (`/api/stats`) that isn't in Coral yet. Add it. A file named `shopapi.yaml` is already waiting at `/root/specs/shopapi.yaml`, containing only a placeholder comment. Open it in a terminal editor:

```bash,run
nano /root/specs/shopapi.yaml
```

Select everything, delete it, and replace it with exactly this content, then save (`Ctrl+O`, Enter, `Ctrl+X` in nano):

```copy
name: shopapi
description: The Reef Shop's own stats API, exposed to agents as SQL
version: 0.1.0
dsl_version: 3
backend: http
base_url: http://localhost:30080
tables:
- name: service_stats
  description: Per-service request success and error counts
  request:
    method: GET
    path: /api/stats
  response:
    rows_path: [stats]
  columns:
  - {name: service, type: Utf8}
  - {name: ok_requests, type: Int64}
  - {name: error_requests, type: Int64}
```

> **Note (finding):** The original track edited this file in a dedicated "Spec Editor" code tab (`/root/specs`, auto-save on change). Labs 2.0's `editor` resource only supports a `container` target, not `vm` - ported as a deviation: editing moved to the Terminal (`nano`) instead of a live code-editor tab.

Then lint and add it from the **Terminal**:

```bash,run
coral source lint /root/specs/shopapi.yaml && coral source add --file /root/specs/shopapi.yaml
```

Lint validates the spec against Coral's schema; add installs it. Success looks like this:

```
Manifest is valid
Added source shopapi (secrets: none)
  * shopapi connected successfully
    shopapi (1 table)
    -- service_stats
```

If lint complains instead, the message names the exact line - fix it in the editor and re-run.

---

## Step 4: Query your API like a database

Your internal API is now a SQL table an agent can reach:

```bash,run
coral sql "SELECT service, ok_requests, error_requests FROM shopapi.service_stats"
```

Two rows - `orders` and `payments`, with live request counts served by *your API* a moment ago. Don't be surprised that `orders` carries the incident's error count while `payments` shows zero: these counters live as long as the pod does, and the fix *redeployed* payments (fresh pod, fresh counters) while orders - the cascade victim - was never restarted. Metrics remember what deploys erase. And because it's in the same catalog, it JOINs against everything else - tickets included:

```bash,run
coral sql "SELECT s.service, s.error_requests, COUNT(t.ticket_id) AS open_tickets FROM shopapi.service_stats s LEFT JOIN shopdata.tickets t ON t.service = s.service AND t.status = 'open' GROUP BY s.service, s.error_requests"
```

`payments` pairs its request stats with its three open tickets - API metrics and business data in one result. That's the full loop: your product's API, in the agent's catalog, joined against business data - read-only, in a YAML file short enough to read in one breath.

---

<instruqt-task id="read_only_by_design"></instruqt-task>

Governance proven, catalog extended. Click **Check** to finish the track - and imagine this demo wearing *your* product's API.
