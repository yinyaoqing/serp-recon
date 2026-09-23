# serp-recon

A small Ruby toolkit for the two questions that come before any SERP parser:

1. **Can a plain HTTP client actually reach this target?** — `SerpRecon::Probe`
2. **Given the HTML, can it be parsed into a contract that survives a redesign?** — `SerpRecon::Engines`

It exists because the first question is usually skipped, and it is the one that
decides whether the project is a weekend or a subscription to a proxy vendor.

Written against two open requests on
[serpapi/public-roadmap](https://github.com/serpapi/public-roadmap):
[#3724 Scrape Wikipedia](https://github.com/serpapi/public-roadmap/issues/3724)
and [#63 Add Google Books API](https://github.com/serpapi/public-roadmap/issues/63),
both `status: freezer`.

## Install

Requires Ruby 3.1+.

```sh
bundle install
bundle exec rake          # offline specs (fixtures only)
LIVE=1 bundle exec rake spec_live   # specs that hit the network
```

## Use

```sh
bin/serp-recon probe                          # reachability table
bin/serp-recon search wikipedia "ruby programming"
bin/serp-recon engines
```

```ruby
require "serp_recon"

payload = SerpRecon.search(engine: "wikipedia", q: "ruby programming")
payload["search_information"]["total_results"]  # => 10459
payload["organic_results"].first["title"]       # => "Ruby (programming language)"
```

The response mirrors SerpApi's published envelope — `search_metadata`,
`search_parameters`, `search_information`, a results key, `pagination` — so a
client written against their Google APIs can read it without a translation layer.

## What the recon found

Measured 2026-09-22 from a residential connection in Taiwan, one request each.
Full writeup: [English](docs/recon-2026-09-22.md) · [繁體中文](docs/recon-2026-09-22.zh-TW.md).

| Target | Status | Verdict |
|---|---|---|
| Wikipedia `Special:Search` | 200 | **reachable** — server-rendered, 20 results |
| Google Books SERP (`tbm=bks`) | 200 | **js_gated** — bootstrap shell, 0 results |
| `books.google.com` legacy search | 302 → 200 | **js_gated** — redirects to the same shell |
| Google Books API v1 (keyless) | 429 | **rate_limited** — shared quota, needs a key |
| g2.com product reviews | 403 | **blocked** — DataDome behind Cloudflare |
| g2.com sitemap (listed in its own robots.txt) | 403 | **blocked** |
| Trustpilot review page | 403 | **blocked** |
| Qwant search API | 403 | **blocked** |

One of eight reachable. That ratio is the reason a SERP API is a business.

## Design notes

**Selector drift fails loudly.** Each engine declares the selectors that must
match. If one stops matching, the parser raises `SelectorDriftError` naming it,
instead of returning `{"title" => nil}` and running quietly for a month:

```
[wikipedia] required selector "li.mw-search-result" matched nothing.
Page title was "Search results". The page layout probably changed;
re-record the fixture and update the parser.
```

**A 200 is not a fetch.** `Fetcher` treats a JavaScript bootstrap shell as a
failure (`JavaScriptGateError`) rather than a successful empty result. Retrying
it is pointless, so it is not retried — unlike a 429 or 5xx, which back off
exponentially with jitter.

**The scrape is checked against an independent source.** Wikipedia publishes the
same query through the MediaWiki API, so `spec/ground_truth_spec.rb` asserts the
scraped total, ordering and word counts agree with the official API — offline,
from a fixture recorded at the same moment as the HTML.

**Fixtures are recorded, never written.** `bin/record_fixture.rb` captures them;
`spec/fixtures/README.md` logs what was captured when, and from where.

**Google Books is not a scraper, on purpose.** The HTML path is a JS gate, and
Google publishes a free documented API over the same corpus. When a first-party
API exists the problem is normalisation, not access. The dead end is kept as a
fixture and a test, because "we checked, here is why not" is the useful artifact.

## Status and limits

- The Wikipedia engine is verified against a recorded fixture and the MediaWiki API.
- **The Google Books field mapping is written from Google's published v1 schema
  and has not been run against a live response** — the keyless quota was
  exhausted (429) while this was written. Record a fixture with your own key and
  `spec/engines/google_books_spec.rb` will check the mapping, including reporting
  any response field the mapper does not read.
- `robots.txt` was read for every target before it was requested. `/search/*` on
  g2.com is `Disallow`ed for `User-agent: *` and is therefore not probed or
  parsed here. Note that robots.txt is a stated policy and not a grant of
  permission — the Terms of Service are a separate question, and this repo takes
  no position on it.
- Probing is one request per target, manual, and not scheduled.

## Licence

MIT.
