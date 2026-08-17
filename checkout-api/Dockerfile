FROM node:24-alpine3.21 AS deps

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci 



COPY . .


RUN npm run build




FROM node:24-alpine3.21

WORKDIR /app

RUN apk upgrade --no-cache

COPY --from=deps /app/package.json /app/package-lock.json ./

RUN npm ci --omit=dev

COPY --from=deps /app/dist ./dist

USER node

EXPOSE 3000

CMD ["npm", "start"]

