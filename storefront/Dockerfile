FROM node:24-alpine3.21 AS deps

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci 

COPY . .

RUN npm run build


FROM nginxinc/nginx-unprivileged:alpine

WORKDIR /app

COPY --from=deps /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf



USER nginx

EXPOSE 8080

