FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS runner
WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=deps /app/node_modules ./node_modules
COPY app.js .

RUN chown -R appuser:appgroup /app
USER appuser

ENV PORT=8080
EXPOSE 8080

CMD ["node", "app.js"]
