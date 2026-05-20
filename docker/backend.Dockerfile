FROM node:20-bookworm-slim

# adb client so the backend can talk to the redroid container.
RUN apt-get update \
 && apt-get install -y --no-install-recommends android-tools-adb ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY backend/package*.json ./backend/
RUN cd backend && npm install --omit=dev

COPY backend ./backend
COPY web ./web

WORKDIR /app/backend
EXPOSE 3000

# adb-start so the daemon is already running when the backend connects.
CMD bash -lc "adb start-server && adb connect ${ADB_SERIAL:-redroid:5555} && node server.js"
