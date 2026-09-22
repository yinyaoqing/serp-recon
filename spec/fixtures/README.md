# Fixtures

Recorded, not hand-written. Each was captured with the date and command below so
it can be re-recorded when a layout changes.

| File | Recorded | Source |
|---|---|---|
| `wikipedia/ruby_programming.html` | 2026-09-22 | `GET en.wikipedia.org/w/index.php?search=ruby+programming&title=Special:Search&fulltext=1` |
| `wikipedia/ruby_programming.api.json` | 2026-09-22 | `GET en.wikipedia.org/w/api.php?action=query&list=search&srsearch=ruby%20programming&srlimit=5&format=json` |
| `google_books/js_gate_shell.html` | 2026-09-22 | `GET google.com/search?tbm=bks&q=ruby+programming` — kept as evidence of the JS gate, not as a parse target |

Missing on purpose: `google_books/volumes.json`. The keyless Books API quota was
exhausted (HTTP 429) when this repo was written. Record one with your own key:

    ruby bin/record_fixture.rb google_books "ruby programming" $GOOGLE_BOOKS_KEY

The mapping spec is pending until that file exists, and will then report any
response field the mapper does not read.
