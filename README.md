# FreshCart

FreshCart is a small grocery delivery app built as part of a platform engineering capstone. It is not a finished product. It is a working codebase that gets containerized, deployed, and monitored as the course progresses. Same app every week, so the work builds on itself.

## What's here

Two services, a database, and the infrastructure to run them all in containers:

- **checkout-api/** — an Express + TypeScript API backed by Postgres. Lists products, handles search, and places orders. Runs as a compiled JavaScript app in production.
- **storefront/** — a static site (Vite + TypeScript, no framework) that calls the checkout API. Builds to plain HTML/CSS/JS and is served by nginx.
- **Postgres** — runs as a container with a named volume for data persistence. Seeded automatically using `checkout-api/db/init.sql`.

## Architecture

Both services are containerized using multi-stage Dockerfiles and connected through Docker Compose on a shared user-defined bridge network.

### Checkout-API Layer Diagram

![Checkout-API multi-stage layer diagram](./api-layout-docker.png)

### Storefront Layer Diagram

![Storefront multi-stage layer diagram](./storefront-layout-docker.png)

### Container Topology

![Docker Compose container topology](./docker-compose-layout.png)
## Running with Docker Compose

Make sure you have Docker and Docker Compose installed. Then:

```
docker compose up --build
```

This starts all three services:

- **Storefront** at `http://localhost:8080`
- **Checkout API** at `http://localhost:3000`
- **Postgres** on port `5432`

The database is seeded automatically on first start using `checkout-api/db/init.sql` mounted into `/docker-entrypoint-initdb.d/`.

Health checks ensure services start in the right order: Postgres must be healthy before the API starts, and the API must be healthy before the storefront starts.

## Running locally without Docker

You will need a Postgres database reachable from your machine and Node.js 20+.

**checkout-api**
```
cd checkout-api
cp .env.example .env      # edit DATABASE_URL to point at your Postgres
npm install
npm run dev                # tsx watch, restarts on save
```

Load `db/init.sql` into your database once to create the schema and seed about 15 products.

Once it is running: `curl localhost:3000/healthz` should return `{"status":"ok"}`, and `curl localhost:3000/api/products` should return the seeded list.

**storefront**
```
cd storefront
npm install
npm run dev
```

Vite's dev server proxies `/api` to `localhost:3000` automatically (see `vite.config.ts`). Open the URL it prints and you should see a product grid you can buy from.

## API reference

| Method | Path | Does |
|---|---|---|
| GET | `/healthz` | Checks the API can reach the database |
| GET | `/api/products` | Lists all products. Add `?search=term` to filter by name |
| GET | `/api/products/:id` | One product |
| POST | `/api/orders` | `{ customerName, customerEmail, items: [{ productId, quantity }] }`. Validates stock, records the order transactionally |
| GET | `/api/orders/:id` | An order and its line items |

## Container images

The checkout-api image is pushed to AWS ECR:

```
055505191746.dkr.ecr.eu-north-1.amazonaws.com/freshcart-checkout-api:1.0.0
```

## Security

- Both services run as non-root users (`USER node` for the API, `USER nginx` for the storefront)
- Base images use Alpine variants for minimal attack surface
- OS packages are patched with `apk upgrade --no-cache` in the final stage
- Images scanned with Docker Scout. Initial scan found 52 vulnerabilities (2 critical). After patching, reduced to 34 (1 critical). Remaining vulnerabilities are in npm internal packages not used by the application and are documented as accepted risk.

## Key decisions

- **node:24-alpine** chosen for small size and minimal attack surface. Pinned version for predictable builds.
- **Layer ordering** places `package.json` before source code so Docker caches dependencies and only rebuilds code changes. Rebuilds went from minutes to seconds.
- **Named volume** (`db_data`) attached only to Postgres because it is the only stateful service. The storefront and API are stateless and can be replaced without data loss.
- **nginx** serves the storefront instead of Node.js because after the Vite build, the output is just static files. No runtime needed, just a web server.
- **nginx.conf** proxies `/api` requests to the checkout-api container since Vite's dev proxy is not available in production.

## Environment variables

**checkout-api** (`.env.example`): `DATABASE_URL`, `PORT`

**storefront** (`.env.example`): `VITE_API_BASE_URL` — leave unset for local dev (the Vite proxy handles it). Set it for a production build where the storefront is deployed separately from the API.

## Blog post

[From "It Works on My Machine" to "It Works on Every Machine": Containerizing a Real App With Docker](https://medium.com/@rachealkuranchie/from-it-works-on-my-machine-to-it-works-on-every-machine-containerizing-a-real-app-with-docker-5b91d06845c8?sharedUserId=rachealkuranchie)