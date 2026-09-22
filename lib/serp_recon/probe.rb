# frozen_string_literal: true

module SerpRecon
  # Answers the question you should ask before writing any parser:
  # "can a plain HTTP client actually reach this, and if not, what is stopping it?"
  #
  # This is the codified version of the manual recon in docs/recon-2026-09-22.md.
  class Probe
    # Response-header and body fingerprints for the common gatekeepers.
    # Identifying *which* one you are facing matters, because the answers differ:
    # a JS gate needs a browser, DataDome needs residential IPs and a real
    # browser, a 429 just needs patience.
    SIGNATURES = [
      { name: "DataDome",   header: /datadome/i,        where: :set_cookie },
      { name: "Cloudflare", header: /cloudflare/i,      where: :server },
      { name: "Akamai",     header: /akamai|_abck/i,    where: :any },
      { name: "PerimeterX", header: /_px|perimeterx/i,  where: :any },
      { name: "Incapsula",  header: /incap_ses|visid/i, where: :any }
    ].freeze

    Finding = Struct.new(
      :label, :url, :status, :bytes, :verdict, :gatekeepers, :js_gate, :notes,
      keyword_init: true
    ) do
      def reachable? = verdict == :reachable

      def to_row
        [label, status || "ERR", "#{bytes}b", verdict.to_s, gatekeepers.join("+"), notes].map(&:to_s)
      end
    end

    def initialize(fetcher: Fetcher.new)
      @fetcher = fetcher
    end

    # targets: { "label" => "https://..." }
    def run(targets)
      targets.map { |label, url| probe_one(label, url) }
    end

    def probe_one(label, url)
      response, gate = @fetcher.probe(url)
      gatekeepers = detect_gatekeepers(response)

      verdict, notes = classify(response, gate, gatekeepers)

      Finding.new(
        label: label, url: url, status: response.status, bytes: response.bytes,
        verdict: verdict, gatekeepers: gatekeepers, js_gate: !gate.nil?, notes: notes
      )
    end

    def self.format_table(findings)
      headers = %w[TARGET STATUS SIZE VERDICT GATEKEEPER NOTES]
      rows = [headers] + findings.map(&:to_row)
      widths = headers.each_index.map { |i| rows.map { |r| r[i].to_s.length }.max }
      rows.map { |r| r.each_with_index.map { |c, i| c.to_s.ljust(widths[i]) }.join("  ").rstrip }
          .insert(1, widths.map { |w| "-" * w }.join("  "))
          .join("\n")
    end

    private

    def detect_gatekeepers(response)
      headers = response.headers || {}
      haystack = headers.map { |k, v| "#{k}: #{v}" }.join("\n")
      SIGNATURES.filter_map do |sig|
        scope =
          case sig[:where]
          when :set_cookie then headers.select do |k, _|
            k.downcase.start_with?("set-cookie")
          end.values.join("\n")
          when :server then headers.fetch("server", "")
          else haystack
          end
        sig[:name] if scope.to_s.match?(sig[:header])
      end.uniq
    end

    def classify(response, gate, gatekeepers)
      return [:error, response.error.to_s] if response.status.nil?

      case response.status
      when 200
        return [:js_gated, "200 but body is a JS bootstrap shell"] if gate

        [:reachable, "server-rendered"]
      when 403
        [:blocked, gatekeepers.empty? ? "403" : "403 by #{gatekeepers.join('+')}"]
      when 429
        [:rate_limited, "429 - back off and retry"]
      when 301, 302, 307, 308
        [:redirect, "-> #{response.headers['location']}"]
      else
        [:error, "HTTP #{response.status}"]
      end
    end
  end
end
