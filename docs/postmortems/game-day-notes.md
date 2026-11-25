7:29 Started rebuild of the cluster freshcart in EKS

07:41 Rebuild stopped: wrong value pasted at Gmail prompt. Script's length check caught it.

07:54 Started fake customers

07:58 to 08:09 Shopper loop stopped (gap in traffic)

"what we learned": add smaller buckets (like 0.01 and 0.025) to see fast requests properly.

8:28 pushed to get deployed

8:34 pushed again to fix trivy scan

08:37  Approved deploy-to-eks. Rollout "successful". Bug is live

8:57 Alert email received: CheckoutApiLatencyFastBurn (page)

09:0x Confirmed: /api/products p50/p95/p99 above 2s. /api/products/:id fine. SLI 88.89%

9:10 Investigation started

9:15 Rolled back with kubectl rollout undo. Healthy version 3a33385 running

9:26 git reverted commit 3a33385 and pushed. Approved deploy-to-eks. Rollout "successful". Bug is gone.