# V2rayMik

درگاه **sing-box** و **Xray** برای RouterOS میکروتیک. یک کانتینر، یک صفحه LAN و بدون نیاز به Winbox برای سوییچ نود.

[![build](https://github.com/zebka/V2rayMik/actions/workflows/build.yml/badge.svg)](https://github.com/zebka/V2rayMik/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/azebka/v2raymik)](https://hub.docker.com/r/azebka/v2raymik)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![English](https://img.shields.io/badge/readme-english-0a7)](README.md)

```
دستگاه LAN ──► RouterOS ──► veth ──► کانتینر (Xray / sing-box) ──► نود شما ──► اینترنت
                   └─ ترافیکِ انتخاب‌شده ──► جدول mik-tunnel (مسدود هنگام قطع تونل)
```

## نصب سریع

**از صفحه Setup Generator شروع کنید: <https://zebka.github.io/V2rayMik/>**

۱. صفحه را باز کنید، scope مورد نظر (`lan`، `list`، `all` یا `manual`) و گزینه‌های دیسک و ریجستری را انتخاب کنید.
۲. دستورات ساخته‌شده را در ترمینال RouterOS پیست و اجرا کنید.
۳. در یک دستگاه داخل LAN به `http://<router>:8081/` بروید، لینک سابسکریپشن را پیست کنید، **Test** بزنید و سپس **Connect** را فشار دهید.

این صفحه فقط خطوط `:global` می‌سازد و اطلاعاتی به سرور ارسال نمی‌کند. ایمپورت دوباره همان ارتقا است.

پیش‌نیازها: RouterOS 7.24+ با پکیج **container**، یک دیسک خارجی و یک نود آماده.

## Scope

| Scope | ترافیکِ تونل | مدیریت روتر |
| --- | --- | --- |
| `lan` (پیشنهادی) | همه کلاینت‌های خصوصی LAN، همراه با هدایت DNS به تونل | در جدول اصلی باقی است |
| `list` | فقط آدرس‌های فهرست `mik-clients` (قابل ویرایش در Winbox) | در جدول اصلی باقی است |
| `all` | LAN و ترافیک خود روتر، رفتار پیش‌فرض 1.3.x | از تونل عبور می‌کند |
| `manual` | هیچ قانونی به طور خودکار، قوانین خودتان را می‌نویسید | دستنخورده |

## مستندات

- `docs/install.md`: نصب، ارتقا، side-load، آینه\u200cها و rollback
- `docs/panel.md`: صفحه LAN، سابسکریپشن، تست و سوییچ نود
- `docs/architecture.md`: مسیر بسته و موتورها
- `docs/troubleshooting.md`: خرابی‌های معمول و راه‌حل

## لایسنس

MIT.
