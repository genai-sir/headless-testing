FROM alpine:3.20
RUN apk add --no-cache curl
COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/monitor.sh
ENTRYPOINT ["/usr/local/bin/monitor.sh"]
