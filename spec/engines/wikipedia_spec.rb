# frozen_string_literal: true

RSpec.describe SerpRecon::Engines::Wikipedia do
  let(:html) { fixture("wikipedia/ruby_programming.html") }
  subject(:payload) { SerpRecon.parse(engine: "wikipedia", html: html, q: "ruby programming") }

  describe "envelope" do
    it "matches the SerpApi response shape" do
      expect(payload.keys).to include(
        "search_metadata", "search_parameters", "search_information",
        "organic_results", "pagination"
      )
      expect(payload.dig("search_parameters", "engine")).to eq("wikipedia")
      expect(payload.dig("search_metadata", "status")).to eq("Success")
    end
  end

  describe "organic_results" do
    let(:results) { payload["organic_results"] }

    it "parses every result on the page" do
      expect(results.size).to eq(20)
    end

    it "numbers positions from 1, using the site's own data-serp-pos" do
      expect(results.map { |r| r["position"] }).to eq((1..20).to_a)
    end

    it "extracts the first result" do
      first = results.first
      expect(first["title"]).to eq("Ruby (programming language)")
      expect(first["link"]).to eq("https://en.wikipedia.org/wiki/Ruby_(programming_language)")
      expect(first["snippet"]).to start_with("Ruby is a general-purpose")
    end

    it "captures the terms the site itself considered a match" do
      expect(results.first["matched_terms"]).to include("Ruby", "programming")
    end

    # Regression: the separator in "64 KB (6,156 words) - 18:41, 1 September 2026"
    # is an en dash, so splitting on " - " returned the entire string as the date.
    it "splits the result metadata into size, word count and edit date" do
      first = results.first

      expect(first["size"]).to eq("64 KB")
      expect(first["word_count"]).to eq(6156)
      expect(first["last_edited"]).to eq("18:41, 1 September 2026")
      expect(first["last_edited"]).not_to include("words")
    end

    it "gives every result a title and an absolute link" do
      aggregate_failures do
        results.each_with_index do |r, i|
          expect(r["title"].to_s).not_to be_empty, "result #{i} has no title"
          expect(r["link"]).to match(%r{\Ahttps://en\.wikipedia\.org/wiki/}),
                               "result #{i} link: #{r['link'].inspect}"
        end
      end
    end
  end

  describe "search_information" do
    it "reads the machine-readable total, not a parsed string" do
      expect(payload.dig("search_information", "total_results")).to eq(10_459)
    end
  end

  describe "selector drift" do
    it "names the selector that broke instead of returning empty results" do
      redesigned = html.gsub("mw-search-result", "totally-new-class-name")

      expect { SerpRecon.parse(engine: "wikipedia", html: redesigned, q: "x") }
        .to raise_error(SerpRecon::SelectorDriftError,
                        /required selector "li\.mw-search-result" matched nothing/)
    end

    it "does not silently succeed on an unrelated page" do
      expect do
        SerpRecon.parse(engine: "wikipedia", html: "<html><title>Error</title><body>nope</body></html>",
                        q: "x")
      end
        .to raise_error(SerpRecon::SelectorDriftError, /Page title was "Error"/)
    end
  end
end
