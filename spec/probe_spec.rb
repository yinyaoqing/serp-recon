# frozen_string_literal: true

RSpec.describe SerpRecon::Probe do
  # A fetcher stub, so the classification logic is testable without the network.
  let(:fake) do
    Class.new do
      def initialize(canned) = @canned = canned

      def probe(url)
        r = @canned.fetch(url)
        # :gate is the second element of the tuple, not a Response member.
        [SerpRecon::Fetcher::Response.new(**r.except(:gate), url: url), r[:gate]]
      end
    end
  end

  def probe_with(canned)
    described_class.new(fetcher: fake.new(canned))
  end

  it "calls a server-rendered 200 reachable" do
    f = probe_with("u" => { status: 200, body: "<html>results</html>", headers: {} }).probe_one("wikipedia",
                                                                                                "u")
    expect(f.verdict).to eq(:reachable)
    expect(f).to be_reachable
  end

  it "separates a JS gate from a real 200" do
    f = probe_with("u" => { status: 200, body: "x", headers: {}, gate: "/httpservice/retry/enablejs" })
        .probe_one("google books", "u")
    expect(f.verdict).to eq(:js_gated)
    expect(f.js_gate).to be(true)
  end

  it "names DataDome behind a Cloudflare edge" do
    headers = { "server" => "cloudflare", "set-cookie" => "datadome=abc; Path=/" }
    f = probe_with("u" => { status: 403, body: "", headers: headers }).probe_one("g2", "u")

    expect(f.verdict).to eq(:blocked)
    expect(f.gatekeepers).to include("DataDome", "Cloudflare")
    expect(f.notes).to eq("403 by DataDome+Cloudflare")
  end

  it "treats 429 as back-off rather than blocked" do
    f = probe_with("u" => { status: 429, body: "", headers: {} }).probe_one("books api", "u")
    expect(f.verdict).to eq(:rate_limited)
  end

  it "renders a table" do
    findings = [probe_with("u" => { status: 200, body: "ok", headers: {} }).probe_one("wikipedia", "u")]
    table = described_class.format_table(findings)

    expect(table).to include("TARGET", "VERDICT", "wikipedia", "reachable")
  end
end
