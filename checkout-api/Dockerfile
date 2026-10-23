FROM node:26-alpine3.24 AS deps

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci 



COPY . .


RUN npm run build




FROM node:26-alpine3.24

WORKDIR /app

RUN apk upgrade --no-cache

COPY --from=deps /app/package.json /app/package-lock.json ./

RUN npm ci --omit=dev \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

COPY --from=deps /app/dist ./dist

USER node

EXPOSE 3000

CMD ["node", "dist/index.js"]

