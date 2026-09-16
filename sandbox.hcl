# Network - foundation for the k8s VM
resource "network" "main" {
  subnet = "10.0.200.0/24"
}

# VM running k3s, the 3-service shop, Prometheus, Coral and Claude Code.
# Matches the original config.yml: ubuntu-2404, 4 CPU, 16GB memory.
resource "vm" "k8s" {
  image {
    name = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  }

  resources {
    cpu    = 4
    memory = 16384
  }

  network {
    id = resource.network.main.meta.id
  }

  # Wired explicitly (not auto-injected) - see the aws_account.bedrock note below.
  # FINDING: `instruqt lab validate` warns that the name-based form
  # (user.student.access_key_id) is "not yet supported by the lab runtime -
  # use the positional form for labs that must run today". Confirms the
  # exact CLI-vs-UI divergence flagged on the group page - using positional
  # here so the lab actually runs; name-based kept as a comment for record.
  # resource.aws_account.bedrock.user.student.access_key_id  (documented, not yet supported)
  environment = {
    AWS_ACCESS_KEY_ID     = resource.aws_account.bedrock.user.0.access_key_id
    AWS_SECRET_ACCESS_KEY = resource.aws_account.bedrock.user.0.secret_access_key
  }

  # Shop frontend (k8s NodePort 30080)
  port {
    local = 30080
  }

  # Prometheus (k8s NodePort 30990)
  port {
    local = 30990
  }

  # Coral UI, proxied from 127.0.0.1:1457 to 0.0.0.0:11457
  port {
    local = 11457
  }

  startup_script = <<EOF
#!/bin/bash
set -euxo pipefail
PS4='+$0[$LINENO]+'

#############################################################
##  coral-ai-sre — track-level setup (host: k8s)           ##
#############################################################

echo "Step 1/8 Waiting for bootstrap, installing k3s..."
until [ -f /opt/instruqt/bootstrap/host-bootstrap-completed ]; do sleep 1; done

# Ubuntu 24.04 host (glibc 2.39 - required by the coral binary, which is
# built against x86_64-unknown-linux-gnu 2.39; no musl build exists).
# k3s is installed here instead of using an instruqt/k3s-* image (those are
# Ubuntu 22.04 / glibc 2.35 and the coral binary refuses to start).
export DEBIAN_FRONTEND=noninteractive
command -v curl >/dev/null 2>&1 || { apt-get -o DPkg::Lock::Timeout=600 update -qq && apt-get -o DPkg::Lock::Timeout=600 install -y -qq curl; }

# Background every network download that doesn't need Kubernetes; each is
# joined (wait + verify) at its first point of use. This overlaps ~30-45s of
# downloads with the k3s install and image pulls.
(
  export CORAL_VERSION="v0.4.1" CORAL_INSTALL_DIR="/usr/local/bin"
  if ! curl -fsSL https://withcoral.com/install.sh | sh; then
    unset CORAL_VERSION
    curl -fsSL https://withcoral.com/install.sh | sh || touch /tmp/coral-install-failed
  fi
) > /tmp/coral-install.log 2>&1 &
CORAL_INSTALL_PID=$!
( curl -fsSL https://claude.ai/install.sh | bash || touch /tmp/claude-install-failed ) > /tmp/claude-install.log 2>&1 &
CLAUDE_INSTALL_PID=$!
(
  mkdir -p /opt/coral-sources
  for SRC in k8s prometheus; do
    curl -fsSL "https://raw.githubusercontent.com/withcoral/coral/v0.4.1/sources/community/$${SRC}/manifest.yaml" \
      -o /opt/coral-sources/$${SRC}.yaml || \
    curl -fsSL "https://raw.githubusercontent.com/withcoral/coral/main/sources/community/$${SRC}/manifest.yaml" \
      -o /opt/coral-sources/$${SRC}.yaml || true
  done
) > /tmp/manifests.log 2>&1 &
MANIFESTS_PID=$!

if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 || { echo "SETUP FAILED: k3s install" >&2; exit 1; }
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

TRIES=0
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 120 ] && { echo "SETUP FAILED: k3s node not Ready after 240s" >&2; exit 1; }
  sleep 2
done
echo "Step 1/8 Completed!"

echo "Step 2/8 Deploying the shop app (frontend, orders, payments)..."
mkdir -p /root/data /root/specs /root/answers /opt/shop

# Zero-dependency Python services: stdlib http.server only, JSON logs to
# stdout, Prometheus text metrics on /metrics, stats JSON on /api/stats.
# Version and failure behavior come from env vars so the "bad deploy" in
# challenge 04 is just an env flip + rollout.
cat > /opt/shop/service.py << 'PYEOF'
import http.server, json, os, random, socketserver, time, urllib.request

SVC = os.environ.get("SVC_NAME", "svc")
VERSION = os.environ.get("SVC_VERSION", "v1")
BROKEN = os.environ.get("PAYMENT_GATEWAY_URL", "") == ""
COUNTS = {"200": 0, "500": 0}

def log(level, msg, req_id):
    print(json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "level": level, "service": SVC, "version": VERSION,
        "request_id": req_id, "message": msg}), flush=True)

PAGE = r'''<!doctype html><html><head><meta charset="utf-8"><title>The Reef Shop</title>
<style>
:root{--bg:#191919;--surface:#2a2a2a;--line:rgba(255,255,255,.1);--txt:rgba(255,255,255,.93);--txt2:rgba(255,255,255,.69);--mut:rgba(255,255,255,.39);--coral:#ff8d62;--green:#b2eaa5;--pink:#e65fa9}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--txt);font-family:system-ui,-apple-system,sans-serif;padding-bottom:70px}
header{display:flex;align-items:center;justify-content:space-between;padding:18px 32px;border-bottom:1px solid var(--line)}
.logo{font-weight:700;font-size:21px;letter-spacing:-.5px}
.logo .mark{margin-right:10px}
.logo small{display:block;color:var(--mut);font-weight:400;font-size:11px;font-family:ui-monospace,monospace;letter-spacing:1.6px;text-transform:uppercase;margin-top:2px}
.cart{font-family:ui-monospace,monospace;font-size:13px;color:var(--txt2);border:1px solid var(--line);border-radius:16px;padding:8px 18px}
.cart b{color:var(--coral)}
main{max-width:1060px;margin:0 auto;padding:30px 32px}
.hero h1{font-size:32px;letter-spacing:-.5px}
.hero p{color:var(--txt2);margin:6px 0 26px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:16px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:20px;display:flex;flex-direction:column;gap:9px;transition:border-color .15s}
.card:hover{border-color:rgba(255,255,255,.25)}
.card .art{font-size:42px}
.card h3{font-size:16px;font-weight:600}
.card .desc{color:var(--mut);font-size:13px;line-height:1.5;flex:1}
.row{display:flex;align-items:center;justify-content:space-between;margin-top:4px}
.price{font-family:ui-monospace,monospace;color:var(--txt2)}
button.buy{background:var(--coral);color:#191919;border:0;border-radius:16px;padding:9px 20px;font-weight:700;font-size:13.5px;cursor:pointer}
button.buy:hover{background:#ff9d78}
button.buy:disabled{opacity:.5;cursor:wait}
#feed{margin-top:32px}
#feed h2{font-size:12px;font-family:ui-monospace,monospace;text-transform:uppercase;letter-spacing:1.6px;color:var(--mut);margin-bottom:8px}
.order{display:flex;gap:10px;font-family:ui-monospace,monospace;font-size:12.5px;color:var(--txt2);padding:7px 0;border-bottom:1px solid var(--line)}
.ok{color:var(--green)}.err{color:var(--pink)}
footer{position:fixed;bottom:0;left:0;right:0;background:rgba(25,25,25,.97);border-top:1px solid var(--line);padding:11px 32px;display:flex;gap:24px;align-items:center;font-family:ui-monospace,monospace;font-size:12px;color:var(--mut)}
.svc{display:flex;gap:7px;align-items:center;color:var(--txt2)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--mut)}
.dot.up{background:var(--green);box-shadow:0 0 6px rgba(178,234,165,.55)}
.dot.down{background:var(--pink);box-shadow:0 0 7px rgba(230,95,169,.7);animation:pulse 1s infinite}
@keyframes pulse{50%%{opacity:.35}}
.toast{position:fixed;top:16px;right:16px;max-width:340px;padding:12px 18px;border-radius:12px;border:1px solid var(--line);background:var(--surface);font-size:13.5px;opacity:0;transform:translateY(-8px);transition:all .25s;pointer-events:none;z-index:9}
.toast.show{opacity:1;transform:none}
.toast.good{border-left:3px solid var(--green)}
.toast.bad{border-left:3px solid var(--pink)}
</style></head><body>
<header>
  <div class="logo"><span class="mark">&#129720;</span>The Reef Shop<small>artisanal coral &middot; sustainably sourced</small></div>
  <div class="cart">orders placed <b id="cartn">0</b></div>
</header>
<main>
  <div class="hero"><h1>Grow something beautiful.</h1><p>Hand-raised coral frags, shipped live from our reef to yours.</p></div>
  <div class="grid" id="grid"></div>
  <div id="feed"><h2>Recent orders</h2><div id="orders"><div class="order" style="color:var(--mut)">no orders yet - be the first</div></div></div>
</main>
<footer><span>live service status</span>
  <span class="svc"><span class="dot up" id="d-frontend"></span>frontend</span>
  <span class="svc"><span class="dot" id="d-orders"></span>orders <span id="c-orders"></span></span>
  <span class="svc"><span class="dot" id="d-payments"></span>payments <span id="c-payments"></span></span>
  <span style="margin-left:auto">source: GET /api/stats</span>
</footer>
<div class="toast" id="toast"></div>
<script>
var P=[
 {e:"🪸",n:"Sunset Torch",d:"Euphyllia with neon tips that sway in the flow. Our signature piece.",p:89},
 {e:"🌺",n:"Golden Hammer Frag",d:"Branching hammer coral, aquacultured, hardy under LEDs.",p:64},
 {e:"🍄",n:"Mushroom Colony",d:"Discosoma rock with six polyps. Perfect for new reefers.",p:39},
 {e:"🌿",n:"Zoanthid Garden",d:"Mixed zoa mat - fire and ice, rastas, utter chaos.",p:54},
 {e:"⭐",n:"Star Polyp Mat",d:"Fast-growing green star polyps for aquascape coverage.",p:29},
 {e:"🔥",n:"Flame Chalice",d:"Slow-growth showpiece with ember rim. Limited run.",p:129}
];
var cart=0,lastErr={orders:0,payments:0},lastGrew={orders:0,payments:0},seen=false;
function el(t,c,h){var x=document.createElement(t);if(c)x.className=c;if(h!==undefined)x.innerHTML=h;return x}
var g=document.getElementById("grid");
P.forEach(function(it,i){
 var c=el("div","card");
 c.appendChild(el("div","art",it.e));
 c.appendChild(el("h3",null,it.n));
 c.appendChild(el("div","desc",it.d));
 var r=el("div","row");
 r.appendChild(el("span","price","$"+it.p+".00"));
 var b=el("button","buy","Buy now");
 b.onclick=function(){buy(b,it)};
 r.appendChild(b);c.appendChild(r);g.appendChild(c);
});
function toast(msg,good){var t=document.getElementById("toast");t.textContent=msg;t.className="toast show "+(good?"good":"bad");setTimeout(function(){t.className="toast"},2600)}
function feed(msg,good){var o=document.getElementById("orders");if(!seen){o.innerHTML="";seen=true}var d=el("div","order");d.innerHTML="<span class=\'"+(good?"ok":"err")+"\'>"+(good?"OK ":"ERR")+"</span> "+new Date().toTimeString().slice(0,8)+" &middot; "+msg;o.insertBefore(d,o.firstChild);while(o.children.length>6)o.removeChild(o.lastChild)}
function buy(btn,it){btn.disabled=true;
 fetch("/buy").then(function(r){
  if(r.ok){cart++;document.getElementById("cartn").textContent=cart;toast("Order placed - "+it.n+" is headed to your reef.",true);feed(it.n+" &middot; $"+it.p+".00",true)}
  else{toast("Checkout failed - payments is not responding.",false);feed(it.n+" &middot; checkout failed",false)}
 }).catch(function(){toast("Checkout failed - store unreachable.",false);feed(it.n+" &middot; unreachable",false)})
 .then(function(){btn.disabled=false;poll()})}
function setDot(svc,state,txt){var d=document.getElementById("d-"+svc);if(d)d.className="dot "+state;var c=document.getElementById("c-"+svc);if(c)c.textContent=txt||""}
function poll(){fetch("/api/stats").then(function(r){return r.json()}).then(function(j){
 setDot("frontend","up");
 j.stats.forEach(function(sv){
  if(sv.error_requests<0){setDot(sv.service,"down","unreachable");return}
  if(sv.error_requests>lastErr[sv.service])lastGrew[sv.service]=Date.now();
  lastErr[sv.service]=sv.error_requests;
  var down=(Date.now()-(lastGrew[sv.service]||0))<45000;
  setDot(sv.service,down?"down":"up",sv.error_requests>0?sv.error_requests+" errs":"")
 })}).catch(function(){setDot("frontend","down");setDot("orders","down");setDot("payments","down")})}
poll();setInterval(poll,4000);
</script>
</body></html>'''

class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        req_id = "req-%06x" % random.randrange(16**6)
        if self.path == "/metrics":
            m = "# TYPE http_requests_total counter\n"
            for code, n in COUNTS.items():
                m += 'http_requests_total{service="%s",status="%s"} %d\n' % (SVC, code, n)
            self._send(200, m, "text/plain"); return
        if self.path == "/healthz":
            self._send(200, '{"ok": true}'); return
        if SVC == "payments" and self.path == "/charge":
            if BROKEN:
                COUNTS["500"] += 1
                log("error", "PAYMENT_GATEWAY_URL is not set; cannot reach payment gateway", req_id)
                self._send(500, '{"error": "payment gateway unreachable"}'); return
            COUNTS["200"] += 1
            log("info", "charge authorized", req_id)
            self._send(200, '{"status": "authorized"}'); return
        if SVC == "orders" and self.path == "/order":
            try:
                with urllib.request.urlopen("http://payments/charge", timeout=3) as r:
                    r.read()
                COUNTS["200"] += 1
                log("info", "order placed", req_id)
                self._send(200, '{"status": "placed"}')
            except Exception:
                COUNTS["500"] += 1
                log("error", "order failed: payments returned an error", req_id)
                self._send(500, '{"error": "order failed"}')
            return
        if SVC == "frontend":
            if self.path == "/api/stats":
                stats = []
                for peer in ("orders", "payments"):
                    try:
                        with urllib.request.urlopen("http://%s/metrics" % peer, timeout=3) as r:
                            text = r.read().decode()
                        ok = err = 0
                        for line in text.splitlines():
                            if line.startswith("http_requests_total"):
                                n = int(float(line.rsplit(" ", 1)[1]))
                                if 'status="500"' in line:
                                    err = n
                                else:
                                    ok += n
                        stats.append({"service": peer, "ok_requests": ok, "error_requests": err})
                    except Exception:
                        stats.append({"service": peer, "ok_requests": 0, "error_requests": -1})
                self._send(200, json.dumps({"stats": stats})); return
            if self.path.startswith("/buy"):
                try:
                    with urllib.request.urlopen("http://orders/order", timeout=5) as r:
                        r.read()
                    COUNTS["200"] += 1
                    log("info", "checkout complete", req_id)
                    self._send(200, '{"status": "placed"}')
                except Exception:
                    COUNTS["500"] += 1
                    log("error", "checkout failed: orders returned an error", req_id)
                    self._send(500, '{"error": "checkout failed - payments unavailable"}')
                return
            COUNTS["200"] += 1
            self._send(200, PAGE, "text/html")
            return
        self._send(404, '{"error": "not found"}')

    def log_message(self, *a):
        pass

socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("", 8000), H) as srv:
    log("info", "service started", "req-000000")
    srv.serve_forever()
PYEOF

kubectl create configmap shop-src --from-file=service.py=/opt/shop/service.py --dry-run=client -o yaml | kubectl apply -f -

for SVC in frontend orders payments; do
cat << MANIFEST_EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $${SVC}
  labels: {app: $${SVC}}
spec:
  replicas: 1
  selector: {matchLabels: {app: $${SVC}}}
  template:
    metadata:
      labels: {app: $${SVC}}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      containers:
      - name: $${SVC}
        image: python:3.11-slim
        command: ["python3", "/app/service.py"]
        env:
        - {name: SVC_NAME, value: "$${SVC}"}
        - {name: SVC_VERSION, value: "v1"}
        - {name: PAYMENT_GATEWAY_URL, value: "http://gateway.internal:9099"}
        ports: [{containerPort: 8000}]
        volumeMounts: [{name: src, mountPath: /app}]
        readinessProbe: {httpGet: {path: /healthz, port: 8000}, initialDelaySeconds: 2}
      volumes:
      - name: src
        configMap: {name: shop-src}
---
apiVersion: v1
kind: Service
metadata:
  name: $${SVC}
  labels: {app: $${SVC}}
spec:
  selector: {app: $${SVC}}
  ports: [{port: 80, targetPort: 8000}]
MANIFEST_EOF
done

kubectl patch svc frontend -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8000,"nodePort":30080}]}}'

echo "Step 2/8 Completed! (rollouts continue in the background; waited on in Step 3)"

echo "Step 3/8 Deploying Prometheus with alert rules..."
cat << 'PROMEOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    rule_files:
    - /etc/prometheus/rules.yml
    scrape_configs:
    - job_name: shop
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [default]
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # scrape ONLY the annotated port (default SD targets every declared
      # container port; without this, multi-port pods produce dead scrapes
      # that trip ShopTargetDown - k3s's traefik did exactly that before
      # the namespace filter above was added)
      - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_prometheus_io_port]
        regex: "(.+);(.+)"
        replacement: "$1:$2"
        target_label: __address__
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: service
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
  rules.yml: |
    groups:
    - name: shop
      rules:
      - alert: PaymentsHighErrorRate
        expr: sum(rate(http_requests_total{service="payments",status="500"}[2m])) > 0.01
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "payments is returning HTTP 500s at a high rate"
          description: "The payments service error rate crossed the SLO threshold."
      - alert: ShopTargetDown
        expr: up{job="shop"} == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "a shop pod stopped answering its scrape"
          description: "One or more shop pods are not being scraped."
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: [pods, services, endpoints]
  verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: prometheus}
subjects:
- {kind: ServiceAccount, name: prometheus, namespace: default}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  labels: {app: prometheus}
spec:
  replicas: 1
  selector: {matchLabels: {app: prometheus}}
  template:
    metadata:
      labels: {app: prometheus}
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v2.53.0
        args: ["--config.file=/etc/prometheus/prometheus.yml", "--web.enable-lifecycle"]
        ports: [{containerPort: 9090}]
        volumeMounts: [{name: config, mountPath: /etc/prometheus}]
      volumes:
      - name: config
        configMap: {name: prometheus-config}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
spec:
  type: NodePort
  selector: {app: prometheus}
  ports: [{port: 9090, targetPort: 9090, nodePort: 30990}]
PROMEOF
# Wait for ALL rollouts here - shop and prometheus image pulls have been
# progressing in parallel since their applies.
for DEP in frontend orders payments prometheus; do
  kubectl rollout status deployment/$${DEP} --timeout=180s || { echo "SETUP FAILED: $${DEP} rollout" >&2; exit 1; }
done
echo "Step 3/8 Completed!"

echo "Step 4/8 Seeding the data plane (JSONL logs + ticket export)..."
cat > /usr/local/bin/shop-traffic << 'TRAFEOF'
#!/bin/bash
# One traffic pulse: browse + buy. Errors are expected while the incident runs.
curl -s -o /dev/null --max-time 5 http://localhost:30080/ || true
curl -s -o /dev/null --max-time 8 http://localhost:30080/buy || true
TRAFEOF
chmod +x /usr/local/bin/shop-traffic

cat > /usr/local/bin/shop-log-harvest << 'HARVEOF'
#!/bin/bash
# Appends the last interval of shop pod logs to /root/data/logs.jsonl.
# Pods emit one JSON object per line, so the export stays valid JSONL.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for SVC in frontend orders payments; do
  POD=$(kubectl get pods -l app=$${SVC} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || continue
  [ -n "$POD" ] || continue
  kubectl logs "$POD" --since=35s 2>/dev/null | sed "s/\"service\": \"$${SVC}\"/\"service\": \"$${SVC}\", \"pod\": \"$${POD}\"/" >> /root/data/logs.jsonl || true
done
grep -h '^{' /root/data/logs.jsonl > /root/data/logs.tmp 2>/dev/null || true
mv /root/data/logs.tmp /root/data/logs.jsonl 2>/dev/null || true
# Self-heal the ticket export if a learner edited it in the code tab.
if [ -f /opt/shop/tickets.bak ]; then
  cmp -s /root/data/tickets.parquet /opt/shop/tickets.bak || cp /opt/shop/tickets.bak /root/data/tickets.parquet
fi
HARVEOF
chmod +x /usr/local/bin/shop-log-harvest
touch /root/data/logs.jsonl

# Ticket export: pre-built Parquet embedded as base64 (6 static rows,
# generated + round-trip-validated at authoring time with pyarrow 25.0.0).
# This replaces an apt update + python3-pip + pyarrow install (~25-40s) and
# the CSV fallback path entirely.
base64 -d > /root/data/tickets.parquet << 'B64EOF'
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QUJBQUlBQUFBQkFBQUFBWUFBQUQ0QUFBQXVBQUFBSXdBQUFCZ0FBQUFNQUFBQUFRQUFBQXcvLy8vQUFBQkJSQUFBQUFZQUFBQUJBQUFBQUFBQUFBR0FBQUFjM1JoZEhWekFBQWMvLy8vV1AvLy93QUFBUVVRQUFBQUhBQUFBQVFBQUFBQUFBQUFDQUFBQUhCeWFXOXlhWFI1QUFBQUFFai8vLytFLy8vL0FBQUJCUkFBQUFBWUFBQUFCQUFBQUFBQUFBQUhBQUFBYzJWeWRtbGpaUUJ3Ly8vL3JQLy8vd0FBQVFVUUFBQUFHQUFBQUFRQUFBQUFBQUFBQndBQUFITjFZbXBsWTNRQW1QLy8vOVQvLy84QUFBRUZFQUFBQUJ3QUFBQUVBQUFBQUFBQUFBb0FBQUJqY21WaGRHVmtYMkYwQUFERS8vLy9FQUFVQUFnQUJnQUhBQXdBQUFBUUFCQUFBQUFBQUFFRkVBQUFBQ0FBQUFBRUFBQUFBQUFBQUFrQUFBQjBhV05yWlhSZmFXUUFBQUFFQUFRQUJBQUFBQT09ABggcGFycXVldC1jcHAtYXJyb3cgdmVyc2lvbiAyNS4wLjAZbBwAABwAABwAABwAABwAABwAAAAxBQAAUEFSMQ==
B64EOF
# Pristine backup: the Data Files code tab is editable, and a learner edit
# would corrupt the export; the harvest loop restores it within 30s.
cp /root/data/tickets.parquet /opt/shop/tickets.bak
echo "Step 4/8 Completed!"

echo "Step 5/8 Installing Coral (pinned)..."
# Joined here: the pinned-release download started in the background at
# Step 1 (guarded; falls back to latest, then to a manual instruction).
wait "$CORAL_INSTALL_PID" || true
cat /tmp/coral-install.log || true
if [ -f /tmp/coral-install-failed ] || ! command -v coral >/dev/null 2>&1; then
  echo "MANUAL FALLBACK: download coral from https://github.com/withcoral/coral/releases and place it at /usr/local/bin/coral" >&2
  exit 1
fi
coral --version
echo "Step 5/8 Completed!"

echo "Step 6/8 Writing source specs and connecting sources..."
# kubectl proxy on 8080 = the k8s community source's default K8S_BASE_URL.
cat > /etc/systemd/system/kubectl-proxy.service << 'UNITEOF'
[Unit]
Description=kubectl proxy for the Coral k8s source
After=network.target
[Service]
Environment="KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
ExecStart=/usr/local/bin/kubectl proxy --port=8080 --address=127.0.0.1
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
UNITEOF

# Stable local Prometheus endpoint on 9090 = the prometheus source default.
cat > /etc/systemd/system/prom-forward.service << 'UNITEOF'
[Unit]
Description=kubectl port-forward for the Coral prometheus source
After=network.target
[Service]
Environment="KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
ExecStart=/usr/local/bin/kubectl port-forward svc/prometheus 9090:9090 --address 127.0.0.1
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl enable --now kubectl-proxy prom-forward

TRIES=0
until curl -fsS http://127.0.0.1:8080/api >/dev/null 2>&1; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 30 ] && { echo "SETUP FAILED: kubectl proxy not answering on 8080" >&2; exit 1; }
  sleep 2
done
TRIES=0
until curl -fsS http://127.0.0.1:9090/-/ready >/dev/null 2>&1; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 30 ] && { echo "SETUP FAILED: prometheus forward not ready on 9090" >&2; exit 1; }
  sleep 2
done

# Joined here: manifest downloads started in the background at Step 1.
wait "$MANIFESTS_PID" || true
for SRC in k8s prometheus; do
  [ -s /opt/coral-sources/$${SRC}.yaml ] || {
    echo "MANUAL FALLBACK: clone github.com/withcoral/coral and run: coral source add --file sources/community/$${SRC}/manifest.yaml" >&2
    exit 1
  }
done

# File-backed spec for the shop's own data plane: JSONL logs + Parquet tickets.
cat > /root/specs/shopdata.yaml << 'SPECEOF'
name: shopdata
description: The Reef Shop data plane - harvested JSONL pod logs and the support ticket export
version: 0.1.0
dsl_version: 3
backend: file
tables:
- name: logs
  description: Application log lines harvested from shop pods (JSON per line)
  format: jsonl
  source:
    location: file:///root/data/
    glob: "logs.jsonl"
  columns:
  - {name: ts, type: Utf8}
  - {name: level, type: Utf8}
  - {name: service, type: Utf8}
  - {name: version, type: Utf8}
  - {name: pod, type: Utf8}
  - {name: request_id, type: Utf8}
  - {name: message, type: Utf8}
- name: tickets
  description: Support ticket export from the helpdesk system
  format: parquet
  source:
    location: file:///root/data/
    glob: "tickets.parquet"
SPECEOF

coral source lint /root/specs/shopdata.yaml || { echo "SETUP FAILED: shopdata spec lint" >&2; exit 1; }

# Canonical backup of the reference spec (learners open this file in ch5 and
# can accidentally overwrite it; ch5 setup restores from here).
cp /root/specs/shopdata.yaml /opt/shop/shopdata.yaml.bak

# Pre-create the ch5 spec file so the learner never touches the code tab's
# new-file/new-folder icons (a live playthrough produced a DIRECTORY named
# shopapi.yaml via the wrong icon - eliminate the whole hazard).
printf '# Challenge 5, Step 3: replace this line with the shopapi spec from the instructions.\n' > /root/specs/shopapi.yaml

# Connect all three sources non-interactively (inputs come from env vars
# named after each spec's declared inputs).
export K8S_BASE_URL="http://127.0.0.1:8080"
export PROMETHEUS_BASE_URL="http://127.0.0.1:9090"
coral source add --file /opt/coral-sources/k8s.yaml || { echo "SETUP FAILED: add k8s source" >&2; exit 1; }
coral source add --file /opt/coral-sources/prometheus.yaml || { echo "SETUP FAILED: add prometheus source" >&2; exit 1; }
coral source add --file /root/specs/shopdata.yaml || { echo "SETUP FAILED: add shopdata source" >&2; exit 1; }
coral source list
coral sql "SELECT schema_name, table_name FROM coral.tables" || echo "WARN: catalog query failed - verify at runtime" >&2
echo "Step 6/8 Completed!"

echo "Step 7/8 Installing Claude Code (Bedrock-backed)..."
# Pattern lifted from ctf-source-lockdown-participant/track_scripts/setup-ide.
# Joined here: the installer started in the background at Step 1.
wait "$CLAUDE_INSTALL_PID" || true
cat /tmp/claude-install.log || true
if [ -f /tmp/claude-install-failed ] || [ ! -x /root/.local/bin/claude ]; then
  echo "SETUP FAILED: claude install (see /tmp/claude-install.log)" >&2
  exit 1
fi
ln -sf /root/.local/bin/claude /usr/local/bin/claude 2>/dev/null || true

# Bedrock wiring lives in Claude Code's OWN config (~/.claude/settings.json
# "env" key), NOT shell rc files - the Instruqt terminal sources no rc file,
# and settings.json env is picked up by every claude launch regardless of
# shell. Pattern: vscode-claude image entrypoint (CLAUDE.md, gcr.io/instruqt/
# vscode-claude). permissions.allow pre-approves the Coral MCP tools so the
# learner is never prompted per tool call (ctf-source-lockdown pattern).
# If Bedrock rejects these model IDs at runtime, pick a current profile from:
#   aws bedrock list-inference-profiles --region us-east-1
mkdir -p /root/.claude
cat > /root/.claude/settings.json << 'ENVEOF'
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-east-1",
    "ANTHROPIC_MODEL": "us.anthropic.claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "us.anthropic.claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "ANTHROPIC_SMALL_FAST_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  },
  "permissions": {
    "allow": ["mcp__coral__*", "Bash(coral sql:*)", "Bash(coral source:*)"]
  }
}
ENVEOF

# Skip Claude Code first-run onboarding (theme/login screens) and pre-trust
# the working directory - the learner should land straight in the REPL.
cat > /root/.claude.json << 'ONBEOF'
{
  "hasCompletedOnboarding": true,
  "theme": "dark",
  "projects": {
    "/root": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true
    }
  }
}
ONBEOF

# AWS creds for Bedrock, wired via the vm's environment block (see sandbox.hcl).
mkdir -p /root/.aws
cat > /root/.aws/credentials << CREDEOF
[default]
aws_access_key_id = $${AWS_ACCESS_KEY_ID:-}
aws_secret_access_key = $${AWS_SECRET_ACCESS_KEY:-}
CREDEOF
printf '[default]\nregion = us-east-1\n' > /root/.aws/config
echo "Step 7/8 Completed!"

echo "Step 8/8 Terminal UX, traffic timer, Coral UI..."
# Coral UI behind a socket-activated systemd proxy so the service tab works
# regardless of the UI's bind address (it defaults to 127.0.0.1:1457).
# Socket-activated proxy (systemd-socket-proxyd ships with Ubuntu 24.04) -
# exposes the loopback-bound Coral UI on 0.0.0.0:11457 with zero packages.
if [ ! -x /lib/systemd/systemd-socket-proxyd ]; then
  echo "MANUAL FALLBACK: systemd-socket-proxyd missing; install socat and forward 0.0.0.0:11457 -> 127.0.0.1:1457" >&2
fi
cat > /etc/systemd/system/coral-ui.service << 'UNITEOF'
[Unit]
Description=Coral local UI
After=network.target
[Service]
ExecStart=/usr/local/bin/coral ui --no-open --port 1457
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
UNITEOF
cat > /etc/systemd/system/coral-ui-forward.socket << 'UNITEOF'
[Unit]
Description=Coral UI forward socket (0.0.0.0:11457)
[Socket]
ListenStream=0.0.0.0:11457
[Install]
WantedBy=sockets.target
UNITEOF
cat > /etc/systemd/system/coral-ui-forward.service << 'UNITEOF'
[Unit]
Description=Proxy Coral UI to the Instruqt service tab
Requires=coral-ui-forward.socket
After=coral-ui.service
[Service]
ExecStart=/lib/systemd/systemd-socket-proxyd 127.0.0.1:1457
UNITEOF
systemctl daemon-reload
systemctl enable --now coral-ui
systemctl enable --now coral-ui-forward.socket

# Traffic + log harvest every 30s (systemd timer survives challenge boundaries).
cat > /etc/systemd/system/shop-pulse.service << 'UNITEOF'
[Unit]
Description=Shop traffic pulse and log harvest
[Service]
Type=oneshot
ExecStart=/usr/local/bin/shop-traffic
ExecStart=/usr/local/bin/shop-log-harvest
UNITEOF
cat > /etc/systemd/system/shop-pulse.timer << 'UNITEOF'
[Unit]
Description=Run shop pulse every 30s
[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
[Install]
WantedBy=timers.target
UNITEOF
systemctl daemon-reload
systemctl enable --now shop-pulse.timer

# Reliable history for engagement checks + kubectl QoL + branded prompt.
# Written to profile.d (login shells) AND /etc/bash.bashrc (interactive
# non-login) AND ~/.bashrc - Instruqt terminals on stock images don't
# reliably source ~/.bashrc alone, which leaves history unflushed and
# breaks history-based check assertions.
cat > /etc/profile.d/reef-shell.sh << 'RCEOF'
if [ -n "$BASH" ]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  export HISTFILE=/root/.bash_history
  export PROMPT_COMMAND='history -a'
  case $- in *i*)
    source <(kubectl completion bash 2>/dev/null) 2>/dev/null || true
    alias k=kubectl
    export PS1='reef-sre:\w$ '
  ;; esac
fi
RCEOF
chmod +x /etc/profile.d/reef-shell.sh
cat >> /etc/bash.bashrc << 'RCEOF'
[ -f /etc/profile.d/reef-shell.sh ] && . /etc/profile.d/reef-shell.sh
RCEOF
cat >> /root/.bashrc << 'RCEOF'
[ -f /etc/profile.d/reef-shell.sh ] && . /etc/profile.d/reef-shell.sh
RCEOF
touch /root/.hushlogin /root/.bash_history

# submit CLI for the incident challenge.
cat > /usr/local/bin/submit << 'SUBEOF'
#!/bin/bash
# Usage: submit "<root-cause-service>"
if [ -z "$${1:-}" ]; then
  echo "Usage: submit \"<the root-cause service>\""
  echo "Tip: several services log errors during a cascade - submit the one whose OWN config is broken."
  exit 1
fi
mkdir -p /root/answers
echo "$1" | tr '[:upper:]' '[:lower:]' | xargs > /root/answers/q1.txt
echo "Answer recorded: $(cat /root/answers/q1.txt)"
echo "Click Check to grade it."
SUBEOF
chmod +x /usr/local/bin/submit

set-workdir /root || true

# Bake first healthy log lines so shopdata.logs is queryable immediately
# (readiness probes already gate the services; short settle only).
sleep 2
/usr/local/bin/shop-traffic || true
/usr/local/bin/shop-log-harvest || true

echo "Step 8/8 Completed! Track setup done."
EOF
}

# AWS account scoped to Bedrock - matches the original config.yml aws_accounts block.
# Known CLI-vs-UI question to confirm/clear (per the group brief): does
# name-based attribute access (user.student.access_key_id) actually work,
# or only positional (user.0.access_key_id)? Wired by name below - that's
# the test.
resource "aws_account" "bedrock" {
  regions  = ["us-east-1", "us-east-2", "us-west-2"]
  services = ["bedrock"]

  user "student" {
    managed_policies = ["arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"]
  }
}
