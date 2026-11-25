# Postmortem: /api/products became slow after the "popular this week" feature

**Date:** November 25, 2026
**Author:** Racheal Kuranchie
**Type:** Game day (incident caused on purpose to test monitoring, runbook and rollback)
**Environment:** FreshCart on Amazon EKS (eu-north-1), Kubernetes 1.36
**Status:** Resolved. Action items in progress

> This was a planned game day. The slow query was simulated with `pg_sleep(2.5)` to act like a real heavy database query. Everything else (the pipeline, the alert, the investigation, the rollback) happened for real.

## 1. Summary

A new "popular this week" feature was deployed to checkout-api through the normal CI/CD pipeline. It added a second database query to `/api/products` that took 2.5 seconds on every request. Every customer browsing products waited more than 2 seconds, breaking our latency SLO.

The pipeline reported the deploy as successful, because the new pods were healthy. The latency burn rate alert caught the problem 20 minutes later and emailed the on call engineer, with a link to the runbook. Following the runbook, the deploy was rolled back in seconds with `kubectl rollout undo`, and a trace showed the exact slow SQL query. The bad commit was then reverted in git and redeployed through the pipeline.

## 2. Impact

| What | Detail |
|---|---|
| Affected route | `/api/products` (product list and search) |
| Not affected | `/api/products/:id` stayed fast (Latency SLI 100%) |
| What customers felt | Every product page took about 2.5 seconds instead of about 50ms. Requests still succeeded (no errors), they were just slow |
| Duration | About **37 minutes** (08:37 to 09:14) |
| Who | Every customer browsing products, not just a few. Even p50 (the typical customer) was above 2 seconds |
| Latency SLI for /api/products (1 hour window) | Dropped from 100% to 88.89% at 09:04, and kept falling to about 72% as slow requests filled the window |
| Alerts fired | CheckoutApiLatencyFastBurn (page) and CheckoutApiLatencySlowBurn (ticket) |

## 3. Timeline

All times are local (GMT). Taken from live notes, GitHub Actions, Grafana and alert emails.

| Time | What happened |
|---|---|
| 07:29 | Started rebuild of the FreshCart EKS cluster with `rebuild.sh` |
| 07:41 | Rebuild stopped: wrong value pasted at the Gmail password prompt. The script's 16 letter check caught it before saving anything. Rebuild re-run |
| 07:54 | Started fake customer traffic (shopper loop) |
| 07:58 to 08:09 | Shopper loop stopped, so there was a gap in traffic. Restarted with `caffeinate` to keep the Mac awake |
| 08:10 to 08:28 | Healthy baseline: p95 about 48ms, Latency SLI 100%, all alerts Normal |
| 08:28 | Pushed the "feat: show popular products this week" commit (b55d35a). Pipeline blocked by Trivy: 2 new HIGH CVEs (body-parser, systeminformation) |
| 08:34 | Pushed a separate commit updating both libraries (0f1eb25). Trivy passed |
| 08:37 | Approved deploy-to-eks. Pipeline said "successfully rolled out". **The slow query was now live** |
| 08:57 | **Alert email received: CheckoutApiLatencyFastBurn (page)**, with the runbook link |
| 08:59 | Alert email received: CheckoutApiLatencySlowBurn (ticket) |
| 09:04 | Confirmed on the dashboard: `/api/products` p50, p95 and p99 above 2s. `/api/products/:id` fine. Latency SLI 88.89% |
| 09:08 | `kubectl get pods`: checkout-api pods 30 minutes old, storefront 80 minutes old. A deploy happened right when the slowness started |
| 09:10 | `kubectl get rs -o wide`: new version 0f1eb25 running, old version 3a33385 on the shelf |
| 09:14 | **Rolled back with `kubectl rollout undo`.** Healthy version 3a33385 running again. p95 dropped back near 0 within a minute or two |
| 09:17 | `git log` showed 2 code changes in the deploy. The feature commit b55d35a changed `/api/products` |
| 09:21 | `git revert b55d35a` failed with a conflict: the feature commit also contained the game day notes and a `.gitignore` change |
| 09:26 | Conflict resolved so the revert only touched the products code. Pushed and approved deploy-to-eks. The CVE fix stayed, the slow query was removed |
| 09:30 to 09:35 | Found the root cause in Tempo: in a slow `/api/products` trace, one `pg.query` span took 2.53s. Its `db.query.text` showed `select p.id from products p, pg_sleep(2.5) order by p.stock asc limit 3` |

## 4. How it was detected

The latency fast burn alert fired by itself and sent an email. Nobody was watching the dashboard or the logs at the time.

**Time to detect: about 20 minutes** (08:37 to 08:57). Slower than expected because:

1. The 1 hour alert window was full of good requests from the baseline, so the slow requests needed time to grow to more than 7.2% of the window.
2. The bug made each fake customer wait 2.5 seconds, so fewer requests per minute arrived.

## 5. Root cause

Using the 5 Whys:

1. **Why were product pages slow?** A new "popular this week" query took 2.5 seconds, and it ran on every `/api/products` request.
2. **Why did it run on every request?** The feature computed "popular" products live, inside the request, instead of ahead of time.
3. **Why did it reach customers?** The pipeline has no check for speed. The `test` job installs packages but runs no tests, and the deploy step only checks that pods are Ready.
4. **Why did the pipeline say the deploy was successful?** The readiness probe checks `/healthz` (can we reach the database?), not whether real routes are fast. Healthy pods can still serve slow pages.
5. **Why did it take 20 minutes to find out?** The only safety net after the pipeline was the SLO alert, which is designed to wait for strong evidence over an hour so it does not wake people for small blips.

**Root cause:** a slow query was added to a hot route, and nothing between `git push` and customers checks how fast the app responds.

**Contributing factors:**
- The feature commit mixed three unrelated changes (code, notes, `.gitignore`), so the revert hit a conflict.
- The runbook was missing some commands (TraceQL query, finding the previous version) and was hard to scan under pressure.

## 6. What went well

- The alert caught the problem on its own, and the email linked straight to the runbook
- Pod ages and `kubectl get rs -o wide` pointed to the deploy within minutes
- `kubectl rollout undo` fixed the customer pain in seconds, without waiting for a pipeline
- The trace showed the exact slow SQL query, so the root cause was proven, not guessed
- Trivy blocked 2 new vulnerabilities before anything was deployed
- Keeping the CVE fix in its own commit meant the revert removed the bug and kept the security fix
- The rebuild script's password length check caught a wrong paste before it caused problems
- The runbook's advice to trust live panels first was correct: p95 recovered in minutes while the SLI and alerts took much longer

## 7. What went badly

- 20 minutes to detect, and about 37 minutes of slow product pages in total
- The pipeline said "successful" while every product page was slow
- `git revert` failed because the feature commit mixed unrelated files
- The runbook was missing the TraceQL query and the commands to find the previous version, and its formatting was hard to follow
- Fake traffic stopped twice (07:58 to 08:09, and around 08:48 to 08:52), which weakens the data
- The slow burn alert fired only 2 minutes after the fast one, because the cluster was only about 1.5 hours old. In a long running cluster it would fire much later

## 8. What we learned

- Healthy pods do not mean a healthy service. Readiness checks if a pod can work, not if it works fast.
- Roll back first, investigate after. `rollout undo` plus `git revert` is fast and safe.
- One commit, one purpose. Mixed commits make reverts messy.
- Histogram buckets decide what you can see: our smallest bucket is 50ms, so fast requests all look like "somewhere under 50ms". Add smaller buckets (0.01 and 0.025).
- SLO alerts protect against real pain, but they are not fast. Faster checks belong in the pipeline.

## 9. Action items

| # | Action | Owner | By when | Status |
|---|---|---|---|---|
| 1 | Update the runbook: add the TraceQL query, `kubectl get rs -o wide`, `git log -- checkout-api/src`, and clearer formatting | Racheal | Nov 25, 2026 | **Done** |
| 2 | Add a post deploy smoke test to `deploy-to-eks`: call `/api/products` several times and fail the pipeline if it is slower than 1 second | Racheal | Dec 2, 2026 | To do |
| 3 | Make the `test` job run real tests (`npm test`) | Racheal | Dec 9, 2026 | To do |
| 4 | Team rule: one commit, one purpose. Keep notes and config changes out of feature commits | Racheal | Nov 25, 2026 | Done |
| 5 | Add smaller histogram buckets (0.01, 0.025) to see fast requests properly | Racheal | Dec 9, 2026 | To do |
| 6 | For future game days, run fake traffic from inside the cluster so a laptop going to sleep cannot stop it | Racheal | Next game day | To do |