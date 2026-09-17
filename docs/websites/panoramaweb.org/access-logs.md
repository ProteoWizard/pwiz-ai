# Website Access Logs 
Essential information for analyzing Tomcat (LabKey server) and Apache Access logs from MacCoss Lab webservers


## Architecture

```
client ──► [client's own proxy, if any: corporate proxy, WARP] ──► Apache (reverse proxy) ──► Tomcat (LabKey Server)
                                                                       └─ same host ─────────────────┘
```

- Apache and Tomcat run on the **same Linux server**. Apache is the public-facing reverse
  proxy; Tomcat only receives requests from Apache over loopback, which is why Tomcat's `%h`
  is always `127.0.0.1`.
- **Every request is logged by Apache. Only requests Apache forwards appear in the Tomcat
  log.** Responses Apache produces itself, such as 429 (rate limiting), 408 (timeouts), and
  the 403 user-agent blocks, appear only in the Apache log.
- **Timing comes only from Tomcat** (`%D`). The Apache log has no duration field.
- **Client IP**:
  - Apache `%h` is the TCP peer: either the real client or an upstream proxy.
  - Apache adds that peer to `X-Forwarded-For` when it proxies to Tomcat. Tomcat's
    `%{X-Forwarded-For}i` is therefore Apache's `%h`, preceded by any `X-Forwarded-For` value
    the client sent (e.g. `93.240.200.190, 163.116.179.15`).
  - **The rightmost entry in Tomcat's X-Forwarded-For is the address Apache saw; entries to
    its left come from the request and can be forged** (see Apache section).
  - Verified on 2026-09-16: for all 263K matched requests, Tomcat's X-Forwarded-For equals
    Apache's `%h`, preceded by Apache's X-Forwarded-For and `, ` when that was set.
- **Timestamps mean different things**: Apache `%t` is when the request **started**; Tomcat
  `%t` is when it **finished**. See "Correlating the two logs".
- **No CDN**: Cloudflare was in front of Apache until July 2026 and has been disabled since.
  Requests that still arrive from Cloudflare IPs come from clients' own Cloudflare services
  (e.g. WARP or Workers), not from our CDN.

### Apache configuration

The Apache config is edited by hand. The `labkey_server.yaml` mentioned in a `mod_qos`
comment is not used.

There are two virtual hosts, `*:80` and `*:443`, with the **same** proxy, logging, and rewrite
rules. Both write to the same `access.log`, and the `forwarded` LogFormat has no port (`%p`)
or protocol field, so **the access log can't show whether a request came in over HTTP or
HTTPS**. Relevant parts of the `*:80` virtual host:

```apache
<VirtualHost *:80>
  ServerName panoramaweb.gs.washington.edu
  ServerAlias panoramaweb-dr.gs.washington.edu panoramaweb.gs.washington.edu daily.panoramaweb.org panoramaweb.org

  <Location "/">
    ProxyPass http://127.0.0.1:8009/ timeout=600
    ProxyPassReverse http://127.0.0.1:8009/
  </Location>
  <LocationMatch "^/(_websocket)">
    ProxyPassMatch ws://127.0.0.1:8009/ timeout=1200
    ProxyPassReverse ws://127.0.0.1:8009/
  </LocationMatch>

  IncludeOptional "/etc/apache2/sites-available/panoramaweb.gs.washington.edu/*.conf"   # directory is empty

  CustomLog ".../access.splunk_kv.log" "splunk_kv"   # no duration either; ignore this log
  CustomLog ".../access.log" "forwarded"        # the log analyzed here

  RewriteEngine On
  RewriteCond %{HTTPS} off
  RewriteRule ^/?(.*) https://%{SERVER_NAME}%{REQUEST_URI} [L,R]          # (1) HTTP -> HTTPS

  RewriteCond %{HTTP_USER_AGENT} ^.*(Bytedance|Bytespider|AhrefsBot|SemrushBot|DotBot|GPTBot|ChatGPT|ClaudeBot|GoogleOther|meta-externalagent|RiboTag-uORF-MSDB|HeadlessChrome).*$ [NC]
  RewriteRule ^ - [F,L]                                                    # (2) named-agent block

  RewriteCond %{HTTP_USER_AGENT} !Dubbotbot [NC]
  RewriteCond %{HTTP_USER_AGENT} ^.*BOT.*$ [NC]
  RewriteRule ^ - [F,L]                                                    # (3) any "bot" block

  RewriteCond %{HTTPS} off
  RewriteRule ^/?(.*) https://%{SERVER_NAME}%{REQUEST_URI} [NE,L,R]       # duplicate of (1), never reached
  RewriteRule ^/labkey(/.*)?$ -> https://panoramaweb.org/... [R=307]       # three rules, summarized
  RewriteCond %{HTTP_HOST} daily.panoramaweb.org   -> https://panoramaweb.org/$1 [R=307]
  RewriteCond %{HTTP_HOST} www.panoramaweb.org     -> https://panoramaweb.org/%{REQUEST_URI} [R]
</VirtualHost>
```

The `*:443` virtual host has the same content, plus:

```apache
  Header always set Strict-Transport-Security "max-age=63072000; includeSubdomains;"
  SSLEngine on
  SSLCertificateFile      "/etc/ssl/certs/panoramaweb.gs.washington.edu.crt"
  SSLCertificateKeyFile   "/etc/ssl/private/panoramaweb.gs.washington.edu.insecure.key"
  # global concurrent limit, issue HTTP 429 thereafter
  QS_LocRequestLimitMatch  "^.*[P|p]anorama%20[P|p]ublic" 25
</VirtualHost>
```

- **The `mod_qos` limit is only in the HTTPS vhost.** Plain-HTTP requests are redirected
  before they could reach it. `QS_ErrorResponseCode 429` is the only server-wide `mod_qos`
  setting.
- In the HTTPS vhost, rule (1) (`%{HTTPS} off`) never fires, so the user-agent blocks
  (2) and (3) are the first rules to run.
- HSTS (`max-age` 2 years) tells browsers to use HTTPS from then on. Most remaining port-80
  traffic is therefore scanners, bots, and first visits.

What this explains in the logs:
- **Apache proxies to Tomcat over HTTP** (`mod_proxy_http`) on port 8009. That is why Tomcat's
  `%h` is `127.0.0.1` and why Apache appends the peer address to X-Forwarded-For.
- **Rewritten URLs in Tomcat's log**:
  - `ProxyPass` without `nocanon` makes `mod_proxy` rebuild the URL in canonical form. It
    decodes characters that don't need encoding (`%40` → `@`, `%2C` → `,`) and keeps the rest
    (`%20`).
  - `ProxyPassMatch ws://127.0.0.1:8009/` appends the full request path to a target that
    already ends in `/`, which produces Tomcat's `//_websocket/notifications`.
- **Redirects that only appear in the Apache log**:
  - rule (1) sends 302s for plain-HTTP requests (~1.6K in the sample);
  - the `/labkey/...` and `daily.` rules send 307s (342: `GET /` 111, `/labkey/...` ~90, and others).
- **On port 80, rule (1) runs before the user-agent blocks**, so blocked agents get a 302 to
  HTTPS rather than a 403 (~820 such lines in the sample, mostly scanners faking bot user
  agents such as `Claude-SearchBot` while requesting `/.env.development` or
  `/home/node/.aws/credentials`). They get the 403 once they follow the redirect.
- **No 502/504s** in the sample, even though Tomcat requests run up to 3,600 s. The
  `timeout=600` in `ProxyPass` is how long Apache waits for Tomcat to send more data, not a
  limit on the whole request, so long streaming downloads aren't cut off.
- Small issues in the rules (not the focus of this doc):
  - the second HTTPS redirect is never reached;
  - the `www.` redirect produces `https://panoramaweb.org//path`, with a doubled slash;
  - the `daily.panoramaweb.org` and `www.panoramaweb.org` conditions have no anchors and
    unescaped dots.


## Tomcat (LabKey server) Access Logs

### Log Format
```
%h %{X-Forwarded-For}i %t "%r" %s %b in:[%{content-length}i] out:[%{content-length}o] %D %S "%{Referer}i" "%{User-Agent}i" %{LABKEY.username}s %q
```

| Field | Description |
|-------|-------------|
| `%h` | Server-side host (always `127.0.0.1`, because Apache proxies over loopback; use `%{X-Forwarded-For}i` for the client IP) |
| `%{X-Forwarded-For}i` | Client IP chain (see Architecture); `-` on a few hundred lines/day |
| `%t` | Timestamp when the request **finished** (start = `%t` − `%D`): `[DD/Mon/YYYY:HH:MM:SS -TZOFF]`, local Pacific time (`-0700` PDT, `-0800` PST) |
| `"%r"` | Request line: `METHOD /path?query HTTP/version` |
| `%s` | HTTP status code |
| `%b` | Response bytes (excluding headers); `-` means zero |
| `in:[...]` | Request `Content-Length` header; `-` if absent |
| `out:[...]` | Response `Content-Length` header; `-` if absent |
| `%D` | **Request processing time in microseconds**; divide by 1,000,000 for seconds |
| `%S` | Tomcat session ID (32-char hex); `-` if no session |
| `"%{Referer}i"` | HTTP Referer header |
| `"%{User-Agent}i"` | HTTP User-Agent header |
| `%{LABKEY.username}s` | Authenticated LabKey username (an email address); `-` for anonymous requests |
| `%q` | Query string (including leading `?`); **`-` when there is no query string** |

### Parsing
Use the regex below to parse a line into named groups.

```python
import re

LINE_RE = re.compile(
    r'^(?P<host>\S+) (?P<forwarded_for>\S+(?:, \S+)*) \[(?P<time>[^\]]+)\]'
    r' "(?P<request>(?:[^"\\]|\\.)*)" (?P<status>\d{3}) (?P<bytes>\S+)'
    r' in:\[(?P<in_cl>[^\]]*)\] out:\[(?P<out_cl>[^\]]*)\]'
    r' (?P<duration_us>\d+) (?P<session>\S+)'
    r' "(?P<referer>(?:[^"\\]|\\.)*)" "(?P<user_agent>(?:[^"\\]|\\.)*)"'
    r' (?P<username>\S+) (?P<query>.*)$'
)
```

Verified against three full days with 0 failures: `access_log.2026-09-14.log` (752,111
lines), `-09-15` (478,283), and `-09-16` (699,365).
Two cases the earlier, simpler regex missed (~1.3% of lines):
- **X-Forwarded-For can be a list**: `93.240.200.190, 163.116.179.15` (~9.4K lines/day,
  e.g. AutoQC clients behind a corporate proxy). See Architecture for which entry to use.
- **Escaped quotes** inside quoted fields: Tomcat writes `"` as `\"` (~200 lines/day, e.g.
  a user agent of `"\"Mozilla/5.0 ...\""`). Unescape `\"` after matching.

Timestamp parsing (read the offset from each line; don't assume `-0700`):
```python
from datetime import datetime
ts = datetime.strptime(time_str, "%d/%b/%Y:%H:%M:%S %z")
```

### Files
- Named `access_log.YYYY-MM-DD.log`, one file per day, rotated by Tomcat itself.
- 480K-750K lines and 200-430 MB per day (09-14: 752K/428 MB, 09-15: 478K/201 MB,
  09-16: 699K/289 MB). Read the file line by line; don't load it into memory.
- A file holds requests that **finished** that day, so a request that started just before
  midnight can appear in the next day's file.

### Key Notes
- **Duration threshold**: >10,000,000 µs = >10 s; >60,000,000 µs = >1 min
- **Exclude WebDAV** for duration analysis: filter out lines where `/_webdav/` appears in the request field. WebDAV entries represent file transfers (large raw files) and skew duration stats.
- **`experiment-showFile.view`** serves Skyline document files over HTTP — slow by nature, similar to WebDAV for performance analysis purposes.
- **`targetedms-downloadDocument.view`** is also a file download; treat it like `experiment-showFile.view`.
- **Exclude WebSockets** (`/_websocket/`, status 101) from duration analysis; they are connection upgrades, not page views.
- **`%D` includes the time spent sending the response**, so slow clients and large downloads
  look slow. Report response size alongside duration.
- **Durations top out near 3,600 s** (1 hour), which looks like a timeout cap.
- **Privacy**: `%{LABKEY.username}s` is the user's email address, and `%q` can contain
  identifiers. Don't copy either into anything shared outside staff.

### Profile of one day (2026-09-14)
- 752K requests; 58K (~8%) authenticated
- Status: 200 (685K), 404 (25K), 302 (19K), 405 (7K), 101 (3.5K), 207 (1.1K, WebDAV)
- Duration: p50 2.4 ms, p95 131 ms, p99 17.1 s; 10.2K requests >10 s, 1.25K >60 s
- Of the >60 s requests, about half are WebDAV. Among page views,
  `targetedms-showPeptideList.view` stands out (~120 requests >60 s)


## Apache Access Logs

### Log Format
```
LogFormat "%h %{X-Forwarded-For}i %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\""
```

| Field | Description |
|-------|-------------|
| `%h` | TCP peer address: the client, or an upstream proxy (Cloudflare, corporate proxy) |
| `%{X-Forwarded-For}i` | X-Forwarded-For **as sent by the peer**; `-` if absent (~98% of lines). **Not trustworthy** (see below) |
| `%l` | identd; always `-` |
| `%u` | HTTP auth user; always `-` (LabKey users are only in the Tomcat log) |
| `%t` | Timestamp, same format and timezone as Tomcat |
| `"%r"` | Request line; `-` for 408 timeouts (no request received) |
| `%>s` | Final HTTP status code |
| `%b` | Response bytes; `-` means zero |
| `"%{Referer}i"` | HTTP Referer header |
| `"%{User-agent}i"` | HTTP User-Agent header; `-` if absent |

**No request duration.** Use the Tomcat log for timing.

### Parsing

```python
import re

APACHE_RE = re.compile(
    r'^(?P<host>\S+) (?P<forwarded_for>-|\S+(?:, \S+)*) (?P<ident>\S+) (?P<user>\S+)'
    r' \[(?P<time>[^\]]+)\] "(?P<request>(?:[^"\\]|\\.)*)" (?P<status>\d{3}) (?P<bytes>\S+)'
    r' "(?P<referer>(?:[^"\\]|\\.)*)" "(?P<user_agent>(?:[^"\\]|\\.)*)"$'
)
```

Verified against `access.log` from 2026-09-16 (00:00-08:31, 281,237 lines, 0 failures). Edge
cases the parser must handle:
- **408 lines have no request**: `"-" 408 - "-" "-"` (~650 in 8.5 h).
- **Garbage request lines** from scanners: TLS handshakes sent to the HTTP port (`\x16\x03\x01...`),
  bare `\n`, and lines without a protocol (~25 in 8.5 h). Don't assume `METHOD PATH PROTO`.
- **X-Forwarded-For lists are not always `, `-separated**: `176.39.81.78,185.53.78.10`
  appears too. Split on `,` and strip whitespace.
- Methods seen: GET, POST, HEAD, plus WebDAV PUT/MOVE/PROPFIND.

### Choosing the client IP
- **Don't take X-Forwarded-For blindly.** In the sample, `185.177.72.23` sent
  `X-Forwarded-For: 127.0.0.1` on 3,557 requests while scanning for secrets
  (`GET /api/.env.production`, user agent `curl/8.7.1`). Using X-Forwarded-For would have
  recorded that scanner as localhost.
- **Use `%h` as the client IP.** The site has had no CDN or load balancer in front of Apache
  since Cloudflare was disabled in July 2026, so there is no proxy whose X-Forwarded-For we
  control. The Tomcat equivalent is the **rightmost** X-Forwarded-For entry.
- Treat X-Forwarded-For as extra information: "this request came through someone's proxy,
  which says the origin was X". It can help group AutoQC or institutional traffic, but it
  must never be used to pick a block target.
- Proxies seen as `%h` with X-Forwarded-For set:
  - **Cloudflare ranges** (`162.158.0.0/15`, `172.64.0.0/13`, `104.16.0.0/13`, ...; ~350
    lines). These are clients' own Cloudflare services, since our Cloudflare setup is disabled.
  - **`163.116.x.x`** (~1,470 lines) and **`147.161.x.x`** (~220 lines): these look like
    corporate security proxies (the ranges are believed to be Netskope and Zscaler). They carry
    AutoQC traffic from institutions. **Blocking one of these addresses would block every user
    behind that proxy.**

### Files
- `access.log`, rotated daily by `logrotate` on Linux.
- The copy process delivers both the **finished rotated file** (`access.log.1`, the previous
  day) and the **current file** (`access.log`, still being written). The current file's last
  line may be cut off mid-write; skip an unparseable final line instead of reporting it as an
  error.
- About 33K lines/hour, which is about 790K lines and 260 MB per day. Read line by line.

### Existing protections
Both are configured in Apache on the web server.

**Rate limiting (429): `mod_qos`**
```apache
# in the *:443 vhost
QS_LocRequestLimitMatch  "^.*[P|p]anorama%20[P|p]ublic" 25
# the only server-wide mod_qos setting
QS_ErrorResponseCode 429
```
- **That is the entire `mod_qos` setup**: one `QS_LocRequestLimitMatch` in the HTTPS vhost
  plus the 429 response code. There are no per-client limits (e.g. `QS_ClientEventLimitCount`,
  `QS_SrvMaxConnPerIP`) and no limits on other URLs.
- **The limit is global, not per client.** At most 25 requests whose URL matches
  `Panorama%20Public` run at once, across all clients. Once 25 are in progress, **every** new
  matching request gets a 429, including requests from real users.
- Checked against the 2026-09-16 sample (00:00-08:31):
  - **All 12,149 429s match the regex**; nothing else produces 429.
  - 158K requests matched the regex; 7.7% of them got a 429.
  - **The 429s came in one flood, 04:48-05:21** (~33 minutes, up to 856 per minute), plus
    14 stray ones. The rest of the window had none.
  - The 429s were spread across **9.5K distinct IPs** (at most 47 per IP). 83% carried the
    same Windows Chrome user agent, and 68% an old `Chrome/1xx.0.0.0` version (see profile).
    The top IPs are in `43.154.x.x` / `43.167.x.x`, which are believed to be Tencent Cloud
    ranges. This is a distributed crawler. The ~17% of 429s with other user agents may
    include real users who were locked out during the flood.
- **Requests that bypass the limit** (the regex only matches the literal text `Panorama%20Public`):
  - **`/__r<N>/` URLs** (container addressed by row ID): 15K requests, **never a 429**. Neither
    log shows which of these are Panorama Public folders, and LabKey has no API to map a row
    ID to a folder path. Report `/__r<N>/` traffic as its own group, keyed by `<N>`.
  - Other spellings: `Panorama%2520Public` (double-encoded, 1,017 requests) and
    `Panorama+Public` (127). Neither matches.
  - Upper-case `PANORAMA%20PUBLIC` would not match either (none seen).
- Regex detail: `[P|p]` is a character class, so it matches `P`, `p`, or `|`. It works, but
  `[Pp]` is what was meant.
- The rule only limits **Panorama Public**. As far as this configuration shows, other folders
  (e.g. `CPTAC Assay Portal`, `TPAD2.0`) have no rate limit.

**User-agent blocks (403): `mod_rewrite`** (rules (2) and (3) in the vhost above)
- **The two rules account for all 403s but 2** (2,801 of 2,803; the other 2 don't come from these rules and are probably from LabKey).
- Rule (2) blocks named agents: GPTBot (265), SemrushBot (86), meta-externalagent (55),
  Bytespider (39), ClaudeBot (31), and others.
- **Rule (3) blocks any user agent containing `bot`** (case-insensitive), except Dubbotbot.
  It accounts for most 403s: bingbot (1,583), Amazonbot (621), AionBot, OAI-SearchBot, GrokBot,
  Reflectionbot, PetalBot, YandexBot, PerplexityBot, and so on.
- **The broad blocking is intentional**, including:
  - search engines: Googlebot (22 requests, all 403) and Applebot (50);
  - link-preview fetchers: Slackbot-LinkExpanding (48), Twitterbot (39), Discordbot (26),
    LinkedInBot (24), TelegramBot (66).
  
  Don't recommend exceptions for them.
- **Dubbotbot is exempt** (174 requests in the sample), presumably on purpose.
- **Crawlers that get through** because they don't say "bot": Baiduspider (all variants
  ~4.7K requests, mostly 200/404) and MathPicDatasetCrawler (500, 200s).
- Many 403s are **scanners faking a bot user agent** (e.g. a `TelegramBot` user agent
  requesting `/home/node/.aws/credentials`). The rule blocks them by accident. Without the
  fake agent they would reach LabKey, so the 403 count overstates real crawler traffic.
- **Not blocked**: `Baiduspider` (+ `-image`, `-render`; ~4.7K requests, mostly 200/404) and
  `MathPicDatasetCrawler` (500, 200s).

### Profile of 8.5 hours (2026-09-16 00:00-08:31)
- 281K requests; status 200 (227K), 302 (24K), 404 (12K), 429 (12K), 403 (2.8K), 101 (1.5K), 408 (650)
- **132K distinct client IPs; 106K made exactly one request.** Most bot traffic comes from
  rotating IPs, so group by user agent, subnet (/24, /16), ASN, and URL pattern, not just IP.
- **The fake-browser user agents are evenly spread**: old Chrome versions (103, 105, 109,
  110, 116, 118, 120, 124, 131, 133) on Windows 10 each account for ~6.5K-21K requests.
  That pattern matches a generated user-agent list, not real browsers.
- 12.8K requests have no user agent (`-`); only 2.6K distinct user agents in total.
- Self-declared crawlers: Baiduspider (all variants ~4.7K), bingbot, Amazonbot,
  MathPicDatasetCrawler, GPTBot, Dubbotbot, AionBot, OAI-SearchBot, GrokBot, TelegramBot.
- **Most requested actions**: `targetedms-showProtein.view` (44K), `targetedms-showPeptide.view` (42K),
  `targetedms-precursorAllChromatogramsChart.view` (19K), `targetedms-showPrecursorList.view` (15K),
  `login-login.view` (11K), `autoQCPing.api` (11K), `login-register.view` (8.7K).
  The volume on `login-register.view` is suspicious.
- **Other traffic**:
  - 15K requests use `/__r<N>/` path prefixes (LabKey container-by-rowId URLs), which crawlers
    use to walk containers.
  - `autoQCPing.api` is legitimate AutoQC traffic; don't flag it.
  - The top single client is `128.208.8.140` (7.4K), a University of Washington address.
  - `check_http/...` is internal monitoring; exclude it or label it.


## Correlating the two logs

Tested on 2026-09-16 00:00-08:31: 281,237 Apache lines and 263,611 Tomcat lines in the
same window.

### Matching rule
- **Key**: normalized request line + client IP, where Apache `%h` = the rightmost entry in
  Tomcat's X-Forwarded-For.
- **Time**: compare Apache `%t` with Tomcat `%t` − `%D`, allowing ±1 s. **Tomcat `%t` is the
  finish time.** All 3,309 uniquely matched requests lasting ≥5 s had Tomcat `%t` ≈ Apache
  `%t` + duration, and none had Tomcat `%t` ≈ Apache `%t`.
- **Normalize the request line before comparing**, because Tomcat logs the URL after Apache
  rewrites it. Of the matched requests, ~9.4K had a different request line in each log:
  - Percent-decoding: Apache `/_webdav/home/%40files/...` → Tomcat `/_webdav/home/@files/...`
    (4.4K). Some characters are decoded and others aren't (e.g. `%2C` → `,`, but `%20` stays).
  - Doubled slashes: Apache `/_websocket/notifications` → Tomcat `//_websocket/notifications` (1.6K).
  - Mixed/partial decoding (3.4K).
  - Cause: `ProxyPass` without `nocanon`, and `ProxyPassMatch` for WebSockets (see Apache
    configuration).
  - Approach that works: split off the query string, `urllib.parse.unquote` the path, collapse
    repeated `/`, and leave the query string as is.
- With that rule, **all but 94 Tomcat requests (99.96%) matched an Apache line.** The 94
  mostly have timestamps right at 00:00, where the Apache line was logged before the sample
  started.

### What only appears in Apache
The 17.7K unmatched Apache lines are responses Apache produced itself:
- 429 rate limiting (12.0K), 403 user-agent blocks (2.8K), 408 timeouts (649), 400 bad requests (54)
- 302 (1.6K): the plain-HTTP → HTTPS redirect; 307 (342): the `/labkey/...` and `daily.`
  redirects (see Apache configuration)
- ~290 others (200/404/206), probably pairing misses on repeated identical requests

### Caveats
- Identical repeated requests from the same IP (e.g. `GET /` polling) can pair with the wrong
  line. Pair each Apache line with the closest unused Tomcat line in time, not the first one found.
- Status codes matched for 99.9% of pairs. The ~275 mismatches (e.g. Apache 429 ↔ Tomcat
  200) are wrong pairings of repeated requests, not real differences.
