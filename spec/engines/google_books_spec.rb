# frozen_string_literal: true

RSpec.describe SerpRecon::Engines::GoogleBooks do
  describe "the HTML path" do
    it "is a JavaScript shell, which is why this engine uses the API" do
      shell = fixture("google_books/js_gate_shell.html")

      expect(shell).to include("/httpservice/retry/enablejs")
      expect(shell.scan("/books?id=")).to be_empty
    end
  end

  describe "against a recorded API response" do
    let(:path) { "google_books/volumes.json" }

    it "normalises volumes into the shared envelope" do
      skip "record spec/fixtures/#{path} with your own API key first" unless fixture?(path)

      payload = SerpRecon.parse(engine: "google_books", html: fixture(path), q: "ruby programming")

      expect(payload.dig("search_parameters", "engine")).to eq("google_books")
      expect(payload["book_results"]).to be_an(Array).and(be_any)
      first = payload["book_results"].first
      expect(first["title"].to_s).not_to be_empty
      expect(first["position"]).to eq(1)
    end

    # Turns the unverified mapping into a test. If Google returns fields this
    # mapper never reads, this fails and names them, rather than dropping them
    # silently forever.
    it "reads every volumeInfo field the response actually contains" do
      skip "record spec/fixtures/#{path} with your own API key first" unless fixture?(path)

      seen = fixture_json(path)["items"].to_a
                                        .flat_map { |i| i["volumeInfo"].to_h.keys }
                                        .uniq
      unmapped = seen - described_class::MAPPED_VOLUME_KEYS

      expect(unmapped).to be_empty,
                          "unmapped volumeInfo fields: #{unmapped.join(', ')}. " \
                          "Map them in #volume or add them to MAPPED_VOLUME_KEYS with a reason."
    end
  end
end
