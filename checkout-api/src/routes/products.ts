import { Router } from "express";
import { pool } from "../db";

export const productsRouter = Router();

productsRouter.get("/products", async (req, res) => {
  const search = typeof req.query.search === "string" ? req.query.search.trim() : "";

  try {
    const result = search
      ? await pool.query(
          "select id, name, category, price_cents, stock from products where name ilike $1 order by name",
          [`%${search}%`]
        )
      : await pool.query("select id, name, category, price_cents, stock from products order by name");

    // New feature: show the 3 "popular this week" products
    const popular = await pool.query(
      "select p.id from products p, pg_sleep(2.5) order by p.stock asc limit 3"
    );

    res.json({ products: result.rows, popular: popular.rows.map((r) => r.id) });
  } catch (error) {
    res.status(500).json({ error: "Could not load products.", detail: (error as Error).message });
  }
});

productsRouter.get("/products/:id", async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    res.status(400).json({ error: "Product id must be an integer." });
    return;
  }

  try {
    const result = await pool.query(
      "select id, name, category, price_cents, stock from products where id = $1",
      [id]
    );

    if (result.rows.length === 0) {
      res.status(404).json({ error: "Product not found." });
      return;
    }

    res.json({ product: result.rows[0] });
  } catch (error) {
    res.status(500).json({ error: "Could not load product.", detail: (error as Error).message });
  }
});
