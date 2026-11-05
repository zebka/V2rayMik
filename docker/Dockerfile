FROM alpine:3.22

ARG XRAY_VERSION=26.10.31
ARG TARGETARCH

RUN apk add --no-cache ca-certificates jq unzip \
 && case "$TARGETARCH" in \
      amd64) asset="Xray-linux-64.zip" ;; \
      arm64) asset="Xray-linux-arm64-v8a.zip" ;; \
      arm)   asset="Xray-linux-arm32-v7a.zip" ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac \
 && wget -qO /tmp/xray.zip \
      "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${asset}" \
 && unzip -q /tmp/xray.zip xray -d /usr/local/bin \
 && chmod +x /usr/local/bin/xray \
 && rm -f /tmp/xray.zip \
 && apk del unzip

COPY entrypoint.sh /app/entrypoint.sh
COPY lib/ /app/lib/

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
