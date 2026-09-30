# Cloudflare: MacCoss Lab Account & panoramaweb.org

Reference record of the MacCoss Lab Cloudflare account and the configuration of the
`panoramaweb.org` domain (zone) within it.

> **Status note:** Cloudflare was in front of the panoramaweb.org Apache server until
> July 2026 and has been disabled since (see
> [access-logs.md](access-logs.md)). This document is a **current + historical
> record** of the account and zone configuration, not a live operations guide.
>
> _Last updated: 2026-09-30._

## Account overview

| Field | Value |
|-------|-------|
| Account name | **MacCoss Lab Account** |
| Account ID | `c167a13e3b30edb37e305fa3827e72f1` |
| Current plan | **Free** |
| Previous plan | Pro (downgraded to Free) |
| Billing | Brian Connolly's personal credit card |

**Budget alert:** A **$5/month** budget alert is configured and sent to all account
member emails, so any unexpected paid usage surfaces immediately.

## Access & authentication

Two members, both with the **Super Admin** role over the entire account:

| Member email | Role | Credentials |
|--------------|------|-------------|
| `bconn@proteinms.net` | Super Admin | Brian Connolly's personal login |
| `skyline-it@proteinms.net` | Super Admin | MacCoss Lab **LastPass** team account, folder `Shared-MacCoss Lab - Skyline` |

- **Login method:** username / password for both accounts.
- **2FA:** not yet configured for either account. _(Recommended follow-up: enable 2FA,
  especially on the shared `skyline-it` account.)_

## Domain / zone: panoramaweb.org

| Field | Value |
|-------|-------|
| Zone status | **Active** |
| Zone plan | Free |
| Registrar | **Network Solutions** |
| Registrar account | Managed by **UW-IT** — changes go through **GSIT support tickets** |
| Nameservers | `rene.ns.cloudflare.com`, `sky.ns.cloudflare.com` |

- The domain is registered at Network Solutions in an account the MacCoss Lab does not
  control directly; registrar-level changes (including nameserver changes) must be
  requested from GSIT via a support ticket.
- Because the domain delegates to Cloudflare's assigned nameservers, **Cloudflare is the
  authoritative DNS provider** for `panoramaweb.org`. This is why the zone remains
  **Active** even though Cloudflare's reverse-proxy / CDN in front of the main Apache
  site is disabled — DNS is still served by Cloudflare; the **apex** record is set to
  DNS-only while several subdomains remain proxied (see [DNS records](#dns-records)).

## DNS records

Cloudflare serves authoritative DNS for the zone. A record's proxy status is shown by
the `cf_tags=cf-proxied:*` flag in a zone export (orange cloud = proxied; grey cloud =
DNS-only). A Cloudflare TTL of **`1` means "Auto"** in the dashboard.

**The main public site (`panoramaweb.org` apex) is DNS-only**, which is how the
Cloudflare proxy in front of Apache was disabled. Several subdomains are still proxied.

### Zone apex / SOA / NS

```
;; SOA
panoramaweb.org.  3600  IN  SOA  rene.ns.cloudflare.com. dns.cloudflare.com. <serial> 10000 2400 604800 3600

;; NS
panoramaweb.org.  86400  IN  NS  rene.ns.cloudflare.com.
panoramaweb.org.  86400  IN  NS  sky.ns.cloudflare.com.
```

### A records

| Name | Target IP | TTL | Proxy | Notes |
|------|-----------|-----|-------|-------|
| `panoramaweb.org` (apex) | `128.208.8.134` | 300 | **DNS-only** | Main site; proxy disabled here |
| `www` | `128.208.8.134` | Auto | Proxied | |
| `daily` | `128.208.8.134` | Auto | Proxied | |
| `maccoss` | `128.208.8.134` | Auto | Proxied | |
| `icpc` | `52.32.114.16` | Auto | Proxied | |
| `icpc-bastion` | `52.13.158.73` | Auto | Proxied | |
| `localhost` | `127.0.0.1` | 300 | DNS-only | |
| `loghost` | `127.0.0.1` | 300 | DNS-only | |

`128.208.8.134` is the panoramaweb Apache origin (UW address space). `icpc` and
`icpc-bastion` point at AWS (`52.x`) addresses.

### CNAME records

| Name | Target | TTL | Proxy | Purpose |
|------|--------|-----|-------|---------|
| `ps` | `labkey-puppeteer-service-alb-1523971373.us-west-2.elb.amazonaws.com` | Auto | DNS-only | Puppeteer Service on AWS ECS Fargate (tagged `puppeteer`) |
| `_9deaedbf5a9dc2f4b5657a8f39c3ed40.ps` | `_1515dbe0a217ca82504582329e9021a6.jkddzztszm.acm-validations.aws.` | 3600 | DNS-only | AWS ACM certificate validation for `ps` |
| `_befcd9727a868a97bae784856a2837c3` | `035a827c822bed8d1550ebb757d73db0.d0d3961033b8b63b65bafb2a457c80af.sectigo.com.` | 300 | DNS-only | Sectigo certificate validation |

The two underscore-prefixed CNAMEs are ACME/CA domain-validation records (AWS Certificate
Manager and Sectigo respectively) and must stay in place for those certificates to renew.

### MX / TXT records

- **MX:** none configured — the zone routes no mail.
- **TXT:** none configured.

## SSL/TLS

| Setting | Value |
|---------|-------|
| Encryption mode (proxied hosts) | **Full (strict)** |
| Edge certificates | Configured (Cloudflare edge) |
| Minimum TLS version | **1.0** |
| Cloudflare Origin Certificate on Apache | **None installed** |

- **Proxied subdomains** (`www`, `daily`, `maccoss`, `icpc`, `icpc-bastion`) go through
  Cloudflare's edge with **Full (strict)**. Because no Cloudflare Origin Certificate is
  installed on Apache, Full (strict) is satisfied by the **publicly-trusted certificate
  installed on Apache** (see the Sectigo / AWS ACM validation CNAMEs under
  [DNS records](#dns-records)) — Cloudflare validates that cert on the origin connection.
- **DNS-only records** (the `panoramaweb.org` apex, `localhost`, `loghost`) bypass the
  Cloudflare edge entirely; TLS for those is terminated by the **SSL certificates
  installed directly in Apache**.
- **Min TLS 1.0** is permissive; raising it to 1.2 is a reasonable hardening follow-up.

## Security (WAF, firewall, rate limiting, bot management)

### Custom rules

There are **3 custom rules**. They apply **only to the proxied DNS records** (traffic
that actually passes through the Cloudflare edge). A request matching any of these rules
**bypasses Cloudflare's bot blocking**:

1. **Allow from GSIT networks** — requests from GSIT network ranges.
2. **Allow requests with `X-Mc-Bypass` HTTP header** — an explicit bypass header for
   trusted clients/automation.
3. **Disable bot protections for non-public projects** — so authenticated / non-public
   project traffic is not challenged as bot traffic.

### Other security settings

| Setting | Value |
|---------|-------|
| Bot Fight Mode | **Enabled** — the bot protection the custom rules above bypass |
| Security Level | **Off** |
| Rate limiting rules | None |
| IP Access Rules | None |

Bot Fight Mode is the active bot protection on proxied traffic; the three custom rules
are the allow-list exceptions to it. With Security Level **Off**, Cloudflare applies no
reputation-based challenge on top of that.

## Rules (page rules / transform / redirect rules)

**None configured** — no Page Rules, Redirect Rules, Transform Rules, or Cache Rules.

## Caching & performance

**All default** — no custom caching level, Browser Cache TTL, or performance settings
have been changed from Cloudflare's defaults. No paid performance features (Argo, Tiered
Cache configuration beyond defaults) are in use on the Free plan.

## Network settings

**All default** — HTTP/2, HTTP/3 (QUIC), WebSockets, IPv6, and other network toggles are
left at Cloudflare's defaults; none were deliberately changed.

## History & timeline

| When | Event |
|------|-------|
| **July 2026** | Cloudflare account/zone set up; DNS for `panoramaweb.org` moved to Cloudflare. |
| July 2026 | Evaluated Cloudflare proxying to **block bots**. Blocking was poor on the lower tiers; upgrading to the **Business** subscription (which blocks more sophisticated bots) worked **very well**. |
| July 2026 | Proxy **disabled** at the apex — Cloudflare's **100 MB upload limit** blocks the large file uploads Panorama/LabKey requires (see email discussion). This is why the `panoramaweb.org` apex is DNS-only. |
| **August 2026** | Subscription reduced **Business → Pro**. |
| **September 2026** | Subscription reduced **Pro → Free** (current). |

**Current disposition:** leave as-is — Cloudflare remains the authoritative DNS provider,
the apex is DNS-only (traffic goes straight to Apache), and several subdomains stay
proxied. The paid bot-blocking proxy is not in use because of the 100 MB upload limit.

> **Why the proxy can't be re-enabled at the apex as-is:** Cloudflare's proxy caps
> request body size at **100 MB** on Business and below (only Enterprise raises it).
> Panorama file uploads routinely exceed that, so proxying the apex breaks uploads
> regardless of how well bot-blocking performs. See the email discussion for details.

## Related documentation

- [access-logs.md](access-logs.md) — Apache/Tomcat access log analysis for panoramaweb.org
