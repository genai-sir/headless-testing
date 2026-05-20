FROM node:20-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git python3 build-essential android-tools-adb ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 https://github.com/NetrisTV/ws-scrcpy.git
WORKDIR /opt/ws-scrcpy
RUN npm install

EXPOSE 8000

# Connect to the redroid sidecar before serving, so it shows up as a device.
CMD bash -lc "adb start-server && adb connect ${ADB_TARGET:-redroid:5555} && npm start"
