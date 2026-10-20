import express from "express";
import { healthRouter } from "./routes/health";
import { productsRouter } from "./routes/products";
import { ordersRouter } from "./routes/orders";
import { metricsRouter } from "./routes/metrics";
import { metricsMiddleware } from "./metrics/httpMetrics";

import { trace } from "@opentelemetry/api";

const tracer = trace.getTracer("checkout-api");

const app = express();
const port = Number(process.env.PORT) || 3000;

app.use(express.json());
app.use(metricsMiddleware);

// Permissive CORS for local/dev use across services. Fine for this course's
// purposes — a real production API would scope this to a known storefront origin.
app.use((_req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  next();
});

app.use(healthRouter);
app.use(metricsRouter);
app.use('/api',productsRouter);
app.use('/api',ordersRouter);

app.get("/api/flaky", (_req, res) => {
  if (Math.random() < 0.2) {
    return res.status(500).json({ error: "something broke" });
  }
  res.json({ ok: true });
});

app.get("/api/slow", (_req, res) => {
  const ms = Math.random() * 3000;

  // Start our own camera, with a clear name
  tracer.startActiveSpan("wait for slow partner", (span) => {
    span.setAttribute("waitedMs", Math.round(ms));

    setTimeout(() => {
      span.end(); // Stop the camera when the wait is over
      res.json({ waitedMs: Math.round(ms) });
    }, ms);
  });
})

// TEMPORARY: for testing the saturation panel. Delete after the lesson!
app.get("/api/busy", (_req, res) => {
  const end = Date.now() + 200;
  while (Date.now() < end) {} // keep the CPU busy for 200ms, doing nothing useful
  res.json({ ok: true });
});

app.listen(port, () => {
  console.log(`FreshCart checkout-api listening on port ${port}`);
});
