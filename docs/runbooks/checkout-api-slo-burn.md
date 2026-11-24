# Runbook: checkout-api SLO burn alerts

Covers these 4 alerts:
- CheckoutApiAvailabilityFastBurn (page)
- CheckoutApiAvailabilitySlowBurn (ticket)
- CheckoutApiLatencyFastBurn (page)
- CheckoutApiLatencySlowBurn (ticket)

## 1. What this means

checkout-api has two promises (SLOs), both 99.5% over 30 days:

| Alert | Promise | A "bad" request is |
|---|---|---|
| Availability | Customers get an answer | A server error (5xx). The customer asked for their order and didn't get it |
| Latency | Customers get it fast | Took longer than 2 seconds. The customer got it, but waited too long |

The alert means we are using up our error budget (the 0.5% of requests allowed to be bad) too fast.

| Type | Looks back over | Fires when | Means |
|---|---|---|---|
| Fast burn (page) | 1 hour | Burn rate above 14.4 | Something broke suddenly. The monthly budget will be gone in about 2 days. Act now |
| Slow burn (ticket) | 6 hours | Burn rate above 6 | Something is going wrong slowly that we might not notice. Fix it in working hours |

Counted: real customer routes, like /api/products and /api/orders.
Skipped: /healthz and /livez (Kubernetes health checks, not customers),
and /api/slow, /api/flaky, /api/busy (test routes that fail on purpose).


## 2. How bad is it

Customers suffer in both cases, and we lose money.

| Alert | What the customer feels | Business impact |
|---|---|---|
| Availability | They try to place an order and get errors. No order goes through | Lost sales. Customers who keep getting errors may never come back |
| Latency | They wait too long for their order. It works, but slowly | Frustrated customers leave before finishing their order |

Availability is usually worse: no answer at all is worse than a slow answer.

| Alert | Urgency |
|---|---|
| AvailabilityFastBurn | PAGE. Act now, before more customers are affected |
| LatencyFastBurn | PAGE. Act now. We are breaking our promise of fast checkout |
| AvailabilitySlowBurn | TICKET. Investigate in working hours: why are small numbers of errors happening over 6 hours? |
| LatencySlowBurn | TICKET. Investigate in working hours: why is checkout slowly getting slower? |

If this continues, we risk breaking our SLA with customers.


## 3. Do this first (stop the pain)

1. Open Grafana and confirm the problem is real:
   kubectl port-forward svc/monitoring-grafana -n monitoring 3002:80
   Open http://localhost:3002, dashboard "FreshCart: checkout-api golden signals".
   Availability alert: is the Error rate panel high?
   Latency alert: is p95 above the 2s red line?
   If both look normal, the problem may have stopped. Watch for 10 minutes.

2. Check for a recent deploy (fastest first):
   kubectl get pods -n freshcart
   Are the checkout-api pods younger than the alert? That is a strong clue.
   kubectl get deployment checkout-api -n freshcart -o jsonpath='{.spec.template.spec.containers[0].image}'
   The tag is the commit hash. Look it up in GitHub Actions to see what changed and who deployed it:
   https://github.com/Racheal777/freshcart-project/actions

3. If a deploy happened just before the alert, roll back in two steps:
   a) Undo now (seconds):
      kubectl rollout undo deployment/checkout-api -n freshcart
      kubectl rollout status deployment/checkout-api -n freshcart
      Wait for "successfully rolled out".
   b) Make it stick (git):
      git revert <commit-hash>
      git push
      Approve the deploy-to-eks job in GitHub Actions.
      Without this step, the next deploy brings the bug back.
   Approvers: Racheal Kuranchie, or backup: (add name).

4. If there was no recent deploy, go to Section 4.


## 4. Find the cause

### 4a. Are the pods healthy?
kubectl get pods -n freshcart

| You see | Means | Next |
|---|---|---|
| Running, 1/1 | Pods are fine | Go to 4b or 4c |
| Running, 0/1 | Pods are alive but not Ready. Readiness checks the database, so checkout-api probably can't reach Neon. Kubernetes stops sending them traffic, so customers get 503s | Check Neon's status page. Check the checkout-api-secrets Secret was not changed |
| CrashLoopBackOff | The app keeps crashing | kubectl logs <pod-name> -n freshcart --previous shows why it crashed |

### 4b. Availability alert: WHY are requests failing?
1. In Grafana Explore, pick Loki, and run:
   {service="checkout-api"} | json | status >= 500
2. Which route is failing? What error message repeats?
3. Click the trace_id on a failing log line to open its trace in Tempo.
4. If the errors mention the database, see 4a.

### 4c. Latency alert: WHERE is it slow?
1. In Grafana Explore, pick Tempo, and open a slow trace for the affected route.
2. Which bar is longest?

| Longest bar | Means | Next |
|---|---|---|
| One pg.query is slow | Probably our code: a heavy query | Find the query, fix it calmly in working hours |
| Every pg.query is slow (even BEGIN) | The database or the network trip to Neon | Check Neon's status page. Escalate if it continues |
| An external call (like a payment partner) | The slowness is outside our app | Contact the partner. Note the incident time and trace IDs as evidence |
| checkout-api's own bars | Our app is overloaded | See 4d |

### 4d. Is the app overloaded?
1. Check the "Saturation: CPU" panel. Is any pod above the 80% line?
2. Check if the autoscaler is already adding pods:
   kubectl get hpa -n freshcart
3. If it is at its maximum, add more pods by hand to share the load:
   kubectl scale deployment checkout-api -n freshcart --replicas=4
4. Look at "Traffic per route": which route jumped? Fix it calmly later, not at 2am.


## 5. How to know it's fixed

1. Right now (within minutes):
   Availability: the "Error rate (5xx)" panel drops back to near 0.
   Latency: the "Latency p95 by route" line drops back below the 2s red line.
   New traces in Tempo for the affected route look normal.
   kubectl get pods -n freshcart shows all checkout-api pods Running and 1/1.

2. Later (the alerts recover slowly, that is normal):
   Fast burn alerts look back over 1 hour, so they can take up to 1 hour to clear.
   Slow burn alerts look back over 6 hours, so they can take up to 6 hours to clear.
   The bad requests are still inside their time window, even after the fix.
   When the alert clears, a "RESOLVED" email arrives.

Do not wait for the alert to clear to decide it is fixed. Trust the live panels first.

## 6. Who to call

If it is not fixed within 30 minutes, escalate:
1. Racheal Kuranchie (054-123-4567, Slack @racheal)
2. Backup: Sarah Johnson (054-987-6543, Slack @sarah)
3. Database (Neon) problems: check https://neonstatus.com first, then contact Neon support.

## 7. After it's fixed

1. Make sure the git revert from Section 3 is done, so the bug does not come back.
2. Write a short note: what happened, what fixed it, and how long it lasted.
3. If customers were affected for more than 30 minutes, or a rollback was needed,
   write a blameless postmortem.
4. Update this runbook if any step was wrong, missing or confusing.