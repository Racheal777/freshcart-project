# Runbook: checkout-api SLO burn alerts

**Last updated:** November 25, 2026, after the products latency game day
**Covers these alerts:**

| Alert | Type | Urgency |
|---|---|---|
| CheckoutApiAvailabilityFastBurn | Availability | PAGE: act now |
| CheckoutApiAvailabilitySlowBurn | Availability | TICKET: working hours |
| CheckoutApiLatencyFastBurn | Latency | PAGE: act now |
| CheckoutApiLatencySlowBurn | Latency | TICKET: working hours |

---

## First 5 minutes (short version)

1. Open Grafana and confirm the problem is real (Section 3, step 1)
2. Check if checkout-api was deployed just before the alert (Section 3, step 2)
3. If yes: **roll back first** with `kubectl rollout undo` (Section 3, step 3)
4. Then find the cause (Section 4) and make the fix stick with `git revert`
5. Write down the time of every step. You will need it for the postmortem

---

## 1. What this means

checkout-api has two promises (SLOs), both 99.5% over 30 days:

| Alert | Promise | A "bad" request is |
|---|---|---|
| Availability | Customers get an answer | A server error (5xx). The customer asked and got nothing |
| Latency | Customers get it fast | Took longer than 2 seconds. The customer got it, but waited too long |

The alert means we are using up our error budget (the 0.5% of requests allowed to be bad) too fast.

| Type | Looks back over | Fires when | Means |
|---|---|---|---|
| Fast burn (page) | 1 hour | Burn rate above 14.4 | Something broke suddenly. The monthly budget will be gone in about 2 days |
| Slow burn (ticket) | 6 hours | Burn rate above 6 | Something is going wrong slowly that we might not notice |

**Counted:** real customer routes, like `/api/products` and `/api/orders`.
**Skipped:** `/healthz` and `/livez` (Kubernetes health checks, not customers), and `/api/slow`, `/api/flaky`, `/api/busy` (test routes that fail on purpose).

---

## 2. How bad is it

| Alert | What the customer feels | Business impact |
|---|---|---|
| Availability | They try to order and get errors. Nothing goes through | Lost sales. Customers who keep getting errors may not come back |
| Latency | They wait too long. It works, but slowly | Frustrated customers leave before finishing |

No answer is worse than a slow answer, so availability alerts are usually more urgent.

If this continues, we risk breaking our SLA with customers.

---

## 3. Do this first: stop the pain

### Step 1. Confirm the problem is real

Open Grafana:

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3002:80
```

Go to http://localhost:3002, dashboard **FreshCart: checkout-api golden signals**.

| Alert | Look at | Problem if |
|---|---|---|
| Availability | Error rate (5xx) panel | Clearly above 0 |
| Latency | Latency by route panel | A route's p95 is above the 2s red line |

Write down **which route** is affected. Is it one route, or all of them?

- One route only: probably a code change to that route
- All routes: probably the database, the network, or the whole app

If everything looks normal, the problem may have stopped. Watch for 10 minutes.

### Step 2. Was there a recent deploy?

**How old are the pods?**

```bash
kubectl get pods -n freshcart
```

If the checkout-api pods are younger than the alert, a deploy probably caused it.

**What is running now, and what ran before?**

```bash
kubectl get rs -n freshcart -o wide
```

| DESIRED | Means |
|---|---|
| 2 | The version running now |
| 0 | An older version, kept "on the shelf" for rollback |

The tag at the end of each IMAGE is a commit hash.

**Which code changed between the two versions?**

```bash
git log --oneline <old-hash>..<new-hash> -- checkout-api/src
```

`-- checkout-api/src` shows only commits that changed the app's code, not config or docs.

### Step 3. If a deploy happened just before the alert, roll back

**3a. Undo now (takes seconds):**

```bash
kubectl rollout undo deployment/checkout-api -n freshcart
kubectl rollout status deployment/checkout-api -n freshcart
```

Wait for `deployment "checkout-api" successfully rolled out`. Then check the old version is back:

```bash
kubectl get rs -n freshcart -o wide
```

**3b. Make the fix stick in git:**

```bash
git revert <bad-commit-hash>
git push
```

Then approve **deploy-to-eks** in GitHub Actions: https://github.com/Racheal777/freshcart-project/actions

Without this step, the next deploy brings the bug back.

> If `git revert` reports a conflict, run `git status`. Keep only the code files in the revert. Use `git restore --staged <file>` for anything else, then `git revert --continue`.

Approvers: Racheal Kuranchie, or backup: (add name).

### Step 4. No recent deploy?

Go to Section 4.

---

## 4. Find the cause

### 4a. Are the pods healthy?

```bash
kubectl get pods -n freshcart
```

| You see | Means | Next |
|---|---|---|
| Running, 1/1 | Pods are fine | Go to 4b or 4c |
| Running, 0/1 | Alive but not Ready. Readiness checks the database, so checkout-api probably cannot reach Neon. Kubernetes stops sending them traffic, so customers get 503s | Check https://neonstatus.com. Check the `checkout-api-secrets` Secret was not changed |
| CrashLoopBackOff | The app keeps crashing | `kubectl logs <pod-name> -n freshcart --previous` shows why |

### 4b. Availability alert: WHY are requests failing?

1. In Grafana **Explore**, pick **Loki**, and run:

   ```
   {service="checkout-api"} | json | status >= 500
   ```

2. Which route is failing? What error message repeats?
3. Click the **trace_id** on a failing log line to open its trace in Tempo.
4. If the errors mention the database, go back to 4a.

### 4c. Latency alert: WHERE is it slow?

1. In Grafana **Explore**, pick **Tempo**, open the **TraceQL** tab.
2. Set the time range to when the problem started.
3. Find slow traces for the affected route (change `products` to your route):

   ```
   { name =~ ".*products.*" && duration > 2s }
   ```

4. Open a trace. Which bar is longest? Click it and read its attributes.

| Longest bar | Means | Next |
|---|---|---|
| One `pg.query` is slow | Probably our code: a heavy query. Its `db.query.text` attribute shows the exact SQL | Find the commit that added it. Roll back if not done yet |
| Every `pg.query` is slow, even `BEGIN` | The database, or the network trip to Neon | Check https://neonstatus.com. Escalate if it continues |
| An external call (like a payment partner) | The slowness is outside our app | Contact the partner with the incident time and trace IDs |
| checkout-api's own bars | Our app is overloaded | Go to 4d |

5. Click **Related logs** on the slow span to see the logs for that exact request.

### 4d. Is the app overloaded?

1. Check the **Saturation: CPU** panel. Is any pod above the 80% line?
2. Is the autoscaler already adding pods?

   ```bash
   kubectl get hpa -n freshcart
   ```

3. If it is at its maximum, add pods by hand:

   ```bash
   kubectl scale deployment checkout-api -n freshcart --replicas=4
   ```

4. Look at **Traffic per route**: which route jumped? Fix it calmly later, not at 2am.

---

## 5. How to know it's fixed

**Right now (within minutes): trust these first**

- Availability: the Error rate (5xx) panel drops back to near 0
- Latency: the affected route's p95 drops back below the 2s red line
- New traces in Tempo for that route look normal
- `kubectl get pods -n freshcart` shows all checkout-api pods Running and 1/1

**Later (slow, and that is normal)**

| Thing | Can take up to | Why |
|---|---|---|
| Latency SLI panel | 1 hour | It looks back over 1 hour |
| Fast burn alert clears | 1 hour | The slow or failed requests are still in its window |
| Slow burn alert clears | 6 hours | Same, with a 6 hour window |

When an alert clears, a **RESOLVED** email arrives.

Do not wait for the alert to clear to decide it is fixed.

---

## 6. Who to call

If it is not fixed within 30 minutes, escalate:

1. Racheal Kuranchie (054-123-4567, Slack @racheal)
2. Backup: Sarah Johnson (054-987-6543, Slack @sarah)
3. Database (Neon) problems: check https://neonstatus.com, then contact Neon support

---

## 7. After it's fixed

1. Make sure the `git revert` from Section 3 is deployed, so the bug does not come back
2. Write a short note: what happened, what fixed it, how long it lasted
3. If customers were affected for more than 30 minutes, or a rollback was needed, write a blameless postmortem
4. Update this runbook if any step was wrong, missing or confusing