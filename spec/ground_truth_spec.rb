# frozen_string_literal: true

# The question a scraper spec usually cannot answer: not "did it run?" but
# "did it parse the right thing?". Wikipedia publishes the same search through
# the MediaWiki API, so the scrape has an independent answer to be checked
# against -- offline, from a fixture recorded at the same moment as the HTML.
RSpec.describe "Wikipedia scrape vs MediaWiki API" do
  let(:scraped) do
    SerpRecon.parse(
      engine: "wikipedia",
      html: fixture("wikipedia/ruby_programming.html"),
      q: "ruby programming"
    )
  end
  let(:api) { fixture_json("wikipedia/ruby_programming.api.json") }

  it "agrees with the API on the total number of hits" do
    expect(scraped.dig("search_information", "total_results"))
      .to eq(api.dig("query", "searchinfo", "totalhits"))
  end

  it "agrees with the API on the ordered titles it returned" do
    api_titles = api.dig("query", "search").map { |r| r["title"] }
    scraped_titles = scraped["organic_results"].first(api_titles.size).map { |r| r["title"] }

    expect(scraped_titles).to eq(api_titles)
  end

  it "agrees with the API on word counts where the HTML exposes them" do
    by_title = api.dig("query", "search").to_h { |r| [r["title"], r["wordcount"]] }

    checked = scraped["organic_results"].filter_map do |r|
      expected = by_title[r["title"]]
      next unless expected && r["word_count"]

      [r["title"], r["word_count"], expected]
    end

    expect(checked).not_to be_empty, "no overlapping results carried a word_count"
    aggregate_failures do
      checked.each do |title, got, expected|
        expect(got).to eq(expected), "#{title}: scraped #{got} words, API says #{expected}"
      end
    end
  end
end

RSpec.describe "live fetch", :live do
  it "fetches and parses Wikipedia end to end" do
    payload = SerpRecon.search(engine: "wikipedia", q: "ruby programming")

    expect(payload["organic_results"]).not_to be_empty
    expect(payload.dig("search_information", "total_results")).to be > 0
  end

  it "reports the Google Books HTML path as a JS gate rather than empty results" do
    fetcher = SerpRecon::Fetcher.new
    expect { fetcher.get("https://www.google.com/search?tbm=bks&q=ruby+programming") }
      .to raise_error(SerpRecon::JavaScriptGateError, /bootstrap shell/)
  end
end
