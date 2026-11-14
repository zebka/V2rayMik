FROM alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f

ARG SING_BOX_VERSION=1.14.4
ARG XRAY_VERSION=26.11.9
ARG TARGETARCH
# The repository's VERSION file, which is also the release tag. CI refuses to
# build a tag that disagrees with it, so the image and the source always match.
ARG VERSION=dev

# Two engines in one image, chosen per node:
#   sing-box — hysteria2, tuic, vless/vmess/trojan/ss, REALITY, ws/grpc/httpupgrade
#   xray     — the above plus xhttp/splithttp and vless encryption=…
# Both downloads are verified against the sha256 GitHub reports for the asset.
# The alpine pin above is the tag's current index digest; bump it deliberately.
RUN apk add --no-cache ca-certificates jq curl busybox-extras \
 && case "$TARGETARCH" in \
      amd64) sb_asset="sing-box-${SING_BOX_VERSION}-linux-amd64-musl.tar.gz"; \
             sb_sha256="8f7c5f0651238850d96a0e488e5473cd77ec1a0098f63942e943f475a12057ca"; \
             xr_asset="Xray-linux-64.zip"; \
             xr_sha256="b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82" ;; \
      arm64) sb_asset="sing-box-${SING_BOX_VERSION}-linux-arm64-musl.tar.gz"; \
             sb_sha256="b95e25f921dc5e17a4cf13327243d1177642c7e35425bf5372862c477c359f56"; \
             xr_asset="Xray-linux-arm64-v8a.zip"; \
             xr_sha256="64ed6858982a7f5eb85d88b811089063bd4f17561f4c8f44e0f1dc8e6f6430be" ;; \
      arm)   sb_asset="sing-box-${SING_BOX_VERSION}-linux-armv7-musl.tar.gz"; \
             sb_sha256="27c225479cd675e6d9b43e3e293c00ace72b693781c4a25b5c0de313d8c712df"; \
             xr_asset="Xray-linux-arm32-v7a.zip"; \
             xr_sha256="19c51e08a6562705fb1cb032a84fd87df21d7e27b194f035be7e754dbe3a97b3" ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac \
 && wget -qO /tmp/sb.tgz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${sb_asset}" \
 && echo "${sb_sha256}  /tmp/sb.tgz" | sha256sum -c - \
 && tar -xzf /tmp/sb.tgz -C /tmp \
 && mv /tmp/sing-box-*/sing-box /usr/local/bin/sing-box \
 && chmod +x /usr/local/bin/sing-box \
 && wget -qO /tmp/xray.zip \
      "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${xr_asset}" \
 && echo "${xr_sha256}  /tmp/xray.zip" | sha256sum -c - \
 && unzip -q -o /tmp/xray.zip xray -d /tmp \
 && mv /tmp/xray /usr/local/bin/xray \
 && chmod +x /usr/local/bin/xray \
 && rm -rf /tmp/sb.tgz /tmp/sing-box-* /tmp/xray.zip

COPY --chmod=755 entrypoint.sh /app/entrypoint.sh
COPY --chmod=755 lib/ /app/lib/
COPY web/ /app/web/
COPY --chmod=755 web/cgi-bin/ /app/web/cgi-bin/
RUN printf '%s\n' "$VERSION" > /app/VERSION \
 && printf '%s\n' "$SING_BOX_VERSION" > /app/SINGBOX_VERSION \
 && printf '%s\n' "$XRAY_VERSION" > /app/XRAY_VERSION
LABEL org.opencontainers.image.version=$VERSION
LABEL org.opencontainers.image.title=v2raymik \
      org.opencontainers.image.source=https://github.com/zebka/V2rayMik \
      org.opencontainers.image.description="MikroTik RouterOS gateway, now with the Xray core alongside sing-box"

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
