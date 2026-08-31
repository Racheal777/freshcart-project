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

RUN npm ci --omit=dev

COPY --from=deps /app/dist ./dist

USER node

EXPOSE 3000

CMD ["npm", "start"]

