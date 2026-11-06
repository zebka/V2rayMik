FROM alpine:3.22

ARG SING_BOX_VERSION=1.14.4
ARG TARGETARCH
# The repository's VERSION file, which is also the release tag. CI refuses to
# build a tag that disagrees with it, so the image and the source always match.
ARG VERSION=dev

# The engine is sing-box: it speaks vless, vmess, trojan, shadowsocks, hysteria2
# and tuic with one config format, and it owns the TUN itself.
RUN apk add --no-cache ca-certificates jq curl busybox-extras \
 && case "$TARGETARCH" in \
      amd64) asset="sing-box-${SING_BOX_VERSION}-linux-amd64-musl.tar.gz" ;; \
      arm64) asset="sing-box-${SING_BOX_VERSION}-linux-arm64-musl.tar.gz" ;; \
      arm)   asset="sing-box-${SING_BOX_VERSION}-linux-armv7-musl.tar.gz" ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac \
 && wget -qO /tmp/sb.tgz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${asset}" \
 && tar -xzf /tmp/sb.tgz -C /tmp \
 && mv /tmp/sing-box-*/sing-box /usr/local/bin/sing-box \
 && chmod +x /usr/local/bin/sing-box \
 && rm -rf /tmp/sb.tgz /tmp/sing-box-*

COPY --chmod=755 entrypoint.sh /app/entrypoint.sh
COPY --chmod=755 lib/ /app/lib/
COPY web/ /app/web/
COPY --chmod=755 web/cgi-bin/ /app/web/cgi-bin/
RUN printf '%s\n' "$VERSION" > /app/VERSION
LABEL org.opencontainers.image.version=$VERSION
LABEL org.opencontainers.image.title=v2raymik

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
