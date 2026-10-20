

# Runbook: /api/slow burning error budget fast

## 1. What this means
Requests to /api/slow are taking longer than 2 seconds far more often than allowed.
Over the last hour, slow requests are happening more than 14.4 times faster than our error budget allows.

## 2. How bad is it
Customers using /api/slow are waiting more than 2 seconds for responses.
Requests still succeed, they are just slow.
At this rate, the monthly error budget will be used up in about 2 days.
This is a page: act now.

## 3. Do this first
1. Open the "FreshCart: checkout-api golden signals" dashboard (http://localhost:3000/public-dashboards/d1d8c231dd4841548d83aa0cf60d9168).
   Look at the Latency SLI panel. Is /api/slow below 99.5%? Is the p95 line above the 2s red line?
   If both look normal, the problem may have already stopped. Watch for 10 minutes.
2. Open GitHub Actions (https://github.com/Racheal777/freshcart-project/actions).
   Was there a deploy in the last 2 hours, or just before the alert started?

3. If yes, roll back that deploy:
   git revert <commit-id-of-that-deploy>
   git push
   Approve the production deploy in GitHub Actions.
   Approvers: Racheal Kuranchie, or backup: (add name).
   Watch the pipeline until it is green.

4. If there was no recent deploy, go to Section 4.

## 4. Find the cause
1. Open a slow /api/slow trace (Traces panel on the dashboard, or Explore → Tempo).
   Which span takes the most time?

2. From that span, click "Logs for this span" to see its logs in Loki.
   Look for error messages.

3. If the database span is slow, or the logs show database connection errors:
   Check the database is healthy: docker compose ps
   Check checkout-api can reach it: curl localhost:3000/healthz
   If the database is unhealthy, escalate (Section 6).

4. If the "Saturation: CPU" panel is above the 80% line:
   Look at "Traffic per route" at the same time. Which route jumped?
   Quick fix: add more instances to share the load.
   Then find the heavy route and fix it calmly, not at 2am.

5. If the slow span is "wait for slow partner":
   The slowness is outside our app. We cannot fix it ourselves.

   Contact the partner, and note the incident time and trace IDs as evidence.

## 5. How to know it's fixed
1. First check what is happening right now:
   The p95 line for /api/slow is back below the 2s red line.
   New /api/slow traces in Tempo are under 2 seconds.

2. Then, within about 1 hour:
   The Latency SLI for /api/slow climbs back above 99.5%.
   
   The alert returns to Normal, and a "Resolved" email arrives.
   Note: the SLI and alert look back over 1 hour, so they recover slowly. That is normal.

## 6. Who to call
If it's not fixed within 30 minutes, escalate:
1. Racheal Kuranchie (054-123-4567, Slack @racheal)
2. Backup: (Sarah Johnson, 054-987-6543, Slack @sarah)

## 7. After it's fixed
Write a short note: what happened, what fixed it, and how long it lasted.
Update this runbook if any step was wrong or missing.