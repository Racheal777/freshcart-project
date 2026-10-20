import {Router} from 'express';
import { collectDefaultMetrics, register } from "prom-client";

collectDefaultMetrics()

export const metricsRouter = Router();

metricsRouter.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});