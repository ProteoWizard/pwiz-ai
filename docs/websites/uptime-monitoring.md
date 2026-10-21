# Uptime Monitoring & Alerts (Grafana Cloud)

Reference for the uptime monitoring of panoramaweb.org and skyline.ms, and for the alert
rules that watch them. Both live in the MacCoss Lab Grafana Cloud stack.

> _Last updated: 2026-10-21._ Check settings change in the Grafana UI. Before relying on
> the tables below, re-read the live state (see [Reading the live state](#reading-the-live-state)).

## Overview

| Field | Value |
|-------|-------|
| Grafana stack | `https://mccss.grafana.net` |
| Uptime monitoring | **Grafana Cloud Synthetic Monitoring** (Testing & synthetics → Synthetics) |
| Metrics datasource | `grafanacloud-prom` (check results are Prometheus metrics) |
| Synthetic Monitoring datasource | `Synthetic Monitoring` (uid `bg1pc5w35upz4f`) |
| Alert rules folder (synthetics) | `Grafana Synthetic Monitoring` (uid `grafana-synthetic-monitoring-app`) |
| Alert rules folder (servers) | `PanoramaWeb` (uid `deswxhfn41xj4f`) |

## Uptime checks (Synthetic Monitoring checks)

All checks are **HTTP** checks that run **every 5 minutes** from **one probe each**.

| Check (job) | Project | Probe | Target URL |
|-------------|---------|-------|------------|
| PanoramaWeb Front Page | panoramaweb | Oregon | `https://panoramaweb.org/project/home/begin.view?` |
| PanoramaWeb Query | panoramaweb | Ohio | `https://panoramaweb.org/home/Example%20Data/targetedms-showSampleFile.view?id=919879` |
| Panorama Web Login Check | panoramaweb | NorthCalifornia | `https://panoramaweb.org/project/MacCoss/bdconnol/begin.view?` |
| PanoramaWeb Files Check (gpfs check) | panoramaweb | NorthVirginia | `https://panoramaweb.org/_webdav/MacCoss/bdconnol/%40files/tests/maccoss-website-checker.txt` |
| Skyline Front Page | skyline | Oregon | `https://skyline.ms/project/home/begin.view?` |
| Skyline Support Board | skyline | Ohio | `https://skyline.ms/announcements/home/support/list.view?.lastFilter=true` |
| skyline.gs.washington.edu File Download | skyline | NorthVirginia | `https://skyline.gs.washington.edu/software/Skyline-release-64_22_2/index.html` |

What each one exercises:

- **Front Page** checks: Apache, Tomcat and LabKey are up and serving pages.
- **PanoramaWeb Query**: a targetedms page that reads from **PostgreSQL**.
- **Login Check**: a page in a MacCoss project folder, so it covers authenticated access.
- **Files Check (gpfs check)**: reads a small test file over WebDAV, so it covers the
  **GPFS file storage** behind `@files`.
- **skyline.gs.washington.edu File Download**: the server that hosts Skyline installers.

Timeouts, assertions and request settings don't appear in the metrics. Check them in the
Synthetics UI.

## Uptime alert rules (Synthetic Monitoring alerts)

Uptime checks are performed using the Synthetic Monitoring feature of GrafanaCloud

The Synthetic Monitoring plugin creates three rules. Each check opts in to them with its own
threshold, which is stored as an `sm_alerts_threshold_*` metric (see below).

| Rule | Fires when | Threshold (all checks unless noted) |
|------|-----------|-------------------------------------|
| **ProbeFailedExecutionsTooHigh [10m]** | Failed checks in the last 10 minutes ≥ threshold | **2** failures |
| **HTTPRequestDurationTooHighAvg [15m]** | Average response time over 15 minutes ≥ threshold | **10000 ms** |
| **TLSTargetCertificateCloseToExpiring** | Days until the TLS certificate expires ≤ threshold | **7 days**, only on the two Front Page checks |

Rule settings: pending period `0s` (they fire on the first evaluation that matches), and
**no data = OK**. Each alert links to the check's Synthetics dashboard.


## Notification routing

| Alerts | Matched by | Contact point | Delivers to |
|--------|-----------|---------------|-------------|
| Synthetic Monitoring rules | label `namespace=synthetic_monitoring` | `skyline-alert@proteinms.net` | `skyline-alert@proteinms.net` (one email to the list) |
| Everything else (server rules) | default policy | `Brian C` | `bconn@proteinms.net` |

Default policy settings: group by `grafana_folder` and `alertname`, group wait 30s, group
interval 5m, **repeat every 4h** while an alert stays firing. No mute timings are set.

## Reading the live state

The Grafana MCP server (`mcp__grafana__*`) can read everything in this document **except
check settings**.

| To find | How |
|---------|-----|
| Current checks, probes, frequency | PromQL: `max by (job, instance, probe, frequency) (sm_check_info)` |
| Alert thresholds per check | PromQL: `{__name__=~"sm_alerts_threshold.*"}` |
| Average latency (ms) | PromQL: `sum by (instance) (rate(probe_all_duration_seconds_sum[15m])) / sum by (instance) (rate(probe_all_duration_seconds_count[15m])) * 1000` |
| Individual check durations | PromQL: `probe_duration_seconds{instance="<url>"}` |
| Success rate, last 24h | PromQL: `100 * sum by (job) (increase(probe_all_success_sum[24h])) / sum by (job) (increase(probe_all_success_count[24h]))` |
| Rules and their state | `alerting_rules_read` (operation `list` / `get`) |
| When an alert fired | `grafana_api_request` on `/api/v1/rules/history?ruleUID=<uid>&from=<unix s>&to=<unix s>`. **Both `from` and `to` are required.** |
| Routing and contact points | `alerting_manage_routing` |

Rule UIDs for the history API: `sm-http-latency-avg-15m-1a06710b`,
`sm-failed-executions-10m-1a06710b` and `sm-certificate-expiry-1a06710b`.

### Creating or changing checks

The MCP server has **no Synthetic Monitoring tools**. Calls through the datasource proxy
(`/api/datasources/proxy/uid/bg1pc5w35upz4f/sm/...`) return **403 "plugin proxy route
access denied"**. To add or edit checks, use one of these:

- **The Grafana UI**: Testing & synthetics → Synthetics → Add new check. Set the alert
  thresholds on the check's Alerting step.
- **The Synthetic Monitoring API**, at `https://synthetic-monitoring-api-<region>.grafana.net/api/v1/check/add`,
  with a Synthetic Monitoring access token (Synthetics → Config) sent as
  `Authorization: Bearer <token>`. This is not a Grafana stack token.
- **Terraform**: the Grafana provider's `grafana_synthetic_monitoring_check` resource.

## Related documentation

- [panoramaweb.org/access-logs.md](panoramaweb.org/access-logs.md): Apache/Tomcat access log analysis, including rate limiting (429s)
- [panoramaweb.org/cloudflare.md](panoramaweb.org/cloudflare.md): DNS and the former Cloudflare proxy
