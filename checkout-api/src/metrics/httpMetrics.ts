import { Request, Response, NextFunction } from "express";
import { Counter, Histogram } from "prom-client";
import { trace } from "@opentelemetry/api";

export const httpRequestsTotal = new Counter({
  name: "http_requests_total",
  help: "Total HTTP requests handled by checkout-api",
  labelNames: ["method", "route", "status_code"],
});

export const httpRequestDuration = new Histogram({
  name: "http_request_duration_seconds",
  help: "How long checkout-api takes to answer, in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 1.5, 2, 2.5, 3, 5],
});

export function metricsMiddleware(req: Request, res: Response, next: NextFunction) {
  if (req.path === "/metrics") return next();

    // Grab this request's name tag while the trace is active
  const traceId = trace.getActiveSpan()?.spanContext().traceId;

  // Start the stopwatch the moment the request arrives
  const stopTimer = httpRequestDuration.startTimer();
   const isHealthCheck = req.path === "/healthz" || req.path === "/livez";

    res.on("finish", () => {
    const labels = {
      method: req.method,
      route: req.route?.path ? `${req.baseUrl}${req.route.path}` : "unmatched",
      status_code: String(res.statusCode),
    };

    httpRequestsTotal.inc(labels);
    const seconds = stopTimer(labels); // the timer returns how long it took, in seconds

    // One structured log line per request
     if (!isHealthCheck) {
    console.log(
      JSON.stringify({
        time: new Date().toISOString(),
        level: res.statusCode >= 500 ? "error" : "info",
        msg: "request completed",
        method: req.method,
        route: labels.route,
        path: req.originalUrl,
        status: res.statusCode,
        durationMs: Math.round(seconds * 1000),
        trace_id: traceId,
      })
    );
}
  });


    next();

}