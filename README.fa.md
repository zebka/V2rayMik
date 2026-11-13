# V2rayMik

**sing-box** و **Xray** روی RouterOS میکروتیک — کافی فقط یک import داشته باشید.

[![build](https://github.com/zebka/V2rayMik/actions/workflows/build.yml/badge.svg)](https://github.com/zebka/V2rayMik/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/azebka/v2raymik)](https://hub.docker.com/r/azebka/v2raymik)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![English](https://img.shields.io/badge/readme-english-0a7)](README.md)

ترافیکِ روتر را از داخلِ یک کانتینر Alpine که Xray و sing-box دارد رد می‌کند. نه tun2socks، نه کانتینرِ دوم، نه فایل‌های geo. یک صفحه‌ی کوچک LAN هم برای سابسکریپشن و سوییچ نود سرو می‌کند — بدون نیاز به Winbox.

## چه نودهایی؟

| نوع نود | موتور |
| --- | --- |
| `vless://`، `vmess://`، `trojan://`، `ss://` | sing-box |
| `hysteria2://`، `hy2://`، `tuic://` | sing-box |
| `type=xhttp` / `splithttp` | **Xray** |
| `vless://…encryption=…` | **Xray** |

هر دو موتور در ایمیج هست؛ انتخاب موتور برای هر نود خودکار است. تراسپورت‌ها: TCP، WebSocket، gRPC، HTTPUpgrade.

## نصب

یک خط روی روتر فایلِ import را دانلود و ایمپورت میکند؛ نیازی به کپی دستی نیست:

```rsc
/tool fetch url="https://raw.githubusercontent.com/zebka/V2rayMik/main/router/v2raymik.rsc" dst-path=v2raymik.rsc; /import file-name=v2raymik.rsc
```

همه‌چیز (veth، mountها، کانتینر، جدول `mik-tunnel`، firewall، dst-nat) را می‌سازد. ایمپورتِ دوباره یعنی upgrade.

کانتینر را اجرا کنید و بگذارید بالا بیاید:

```rsc
/container/start [find where name="v2raymik"]
```

از یک دستگاه روی همان LAN بروید به `http://<router>:8081/` (بدون پسورد). لینک سابسکریپشن را پیست کنید، **Test** بزنید و روی نودِ دلخواه **Connect** بزنید. همین؛ روتر و همه‌ی کلاینت‌های پشتِ آن از همان نود وصل می‌شوند.

برای حذف: `:global MikMode "uninstall"` و دوباره import. راهنمای کامل، آینه‌ی ایرانی، side-load و rollback در `docs/install.md`.

اگر روتر به GitHub دسترسی ندارد، `router/v2raymik.rsc` را دانلود و دستی `import` کنید.

## پیش‌نیازها

- RouterOS 7.24+ با پکیج **container** (روی 7.25.1 تست شده)
- فعال بودن حالت container — نیازمند دسترسی فیزیکی یک‌بار
- یک دیسک خارجی برای root-dir کانتینر
- سرور proxy خودتان (vless، vmess، trojan، ss، hysteria2، tuic)

## مستندات

- `docs/install.md` — نصب، ارتقا، side-load، آینه‌ها، rollback
- `docs/architecture.md` — مسیر بسته، موتورها، چرا دو مسیر `/1`
- `docs/panel.md` — صفحه‌ی مدیریت LAN: سابسکریپشن، تست، سوییچ
- `docs/security.md` — allowlist خروجی، fail-closed، credentials
- `docs/troubleshooting.md` — خرابی‌های معمول و راه‌حل
- `docs/benchmarks.md` — سرعت اندازه‌گیری‌شده روی دستگاه مرجع
- `docs/migration.md` — انتقال از ۱.۰.x
- `docs/dockerhub.md` — صفحه‌ی Docker Hub
- `docs/design/admin-ui.md` — سند طراحی پنل

## لایسنس

MIT.
