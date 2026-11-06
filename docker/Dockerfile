FROM alpine:3.22

ARG XRAY_VERSION=26.10.31
ARG TARGETARCH
# The repository's VERSION file, which is also the release tag. CI refuses to
# build a tag that disagrees with it, so the image and the source always match.
ARG VERSION=dev

RUN apk add --no-cache ca-certificates jq curl unzip busybox-extras \
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

COPY --chmod=755 entrypoint.sh /app/entrypoint.sh
COPY --chmod=755 lib/ /app/lib/
COPY web/ /app/web/
COPY --chmod=755 web/cgi-bin/ /app/web/cgi-bin/
RUN printf '%s\n' "$VERSION" > /app/VERSION
LABEL org.opencontainers.image.version=$VERSION

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
