# frozen_string_literal: true

require "cgi"

module SerpRecon
  module Engines
    # Addresses serpapi/public-roadmap#3724 ("[New API] Scrape Wikipedia",
    # status: freezer).
    #
    # Wikipedia's Special:Search is fully server-rendered, which in 2026 makes
    # it a genuine outlier -- see docs/recon-2026-09-22.md. It also exposes
    # data-serp-pos on each result and a machine-readable total on the
    # results-info div, so the scrape can be checked against the MediaWiki API.
    class Wikipedia < Base
      engine "wikipedia"
      results_key_is "organic_results"
      live_fetch true
      requires "li.mw-search-result", ".mw-search-result-heading a"

      BASE = "https://%<lang>s.wikipedia.org"

      # "64 KB (6,156 words) - 18:41, 1 September 2026"
      #
      # The separator is an en dash (U+2013), not a hyphen, and it is a
      # non-breaking one in some skins. Splitting on " - " silently returns the
      # whole string instead of the date, so match the dash class explicitly.
      DATA_SEPARATOR = /\s*[-‐-―]\s*/

      def initialize(q:, lang: "en", limit: 20, offset: 0, **rest)
        super
      end

      def url
        host = format(BASE, lang: params[:lang])
        query = {
          search: params[:q],
          title: "Special:Search",
          fulltext: 1,
          limit: params[:limit],
          offset: params[:offset]
        }.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
        "#{host}/w/index.php?#{query}"
      end

      # Ground-truth counterpart. The specs assert that what we scraped agrees
      # with what the official API reports for the same query.
      def api_url
        host = format(BASE, lang: params[:lang])
        query = {
          action: "query", list: "search", srsearch: params[:q],
          srlimit: params[:limit], sroffset: params[:offset], format: "json"
        }.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
        "#{host}/w/api.php?#{query}"
      end

      private

      def extract(doc)
        {
          results: doc.css("li.mw-search-result").map.with_index { |li, i| result_from(li, i) },
          total_results: total_results(doc),
          pagination: pagination(doc)
        }
      end

      def result_from(li, index)
        link = li.at_css(".mw-search-result-heading a")
        host = format(BASE, lang: params[:lang])

        {
          "position" => (link&.[]("data-serp-pos")&.to_i || index) + 1,
          "title" => squish(link&.[]("title") || link&.text),
          "link" => link && "#{host}#{link['href']}",
          "snippet" => squish(li.at_css(".searchresult")&.text),
          # The terms Wikipedia itself considered a match. Useful, and free:
          # it is the site telling you why this result was returned.
          "matched_terms" => li.css(".searchresult .searchmatch").map { |s| squish(s.text) }.uniq,
          "thumbnail" => thumbnail(li)
        }.merge(result_meta(li)).compact
      end

      def thumbnail(li)
        src = li.at_css(".searchResultImage-thumbnail img")&.[]("src")
        return nil unless src

        src.start_with?("//") ? "https:#{src}" : src
      end

      def result_meta(li)
        raw = squish(li.at_css(".mw-search-result-data")&.text)
        return {} if raw.empty?

        tail = raw.split(DATA_SEPARATOR, 2)[1]

        {
          "word_count" => raw[/([\d,]+)\s+words?/, 1]&.delete(",")&.to_i,
          "size" => raw[/\A([\d,.]+\s*[KMG]?B)/, 1],
          "last_edited" => tail && squish(tail)
        }.compact
      end

      def total_results(doc)
        doc.at_css(".results-info")&.[]("data-mw-num-results-total")&.to_i
      end

      def pagination(doc)
        host = format(BASE, lang: params[:lang])
        nxt = doc.at_css(".mw-nextlink")
        prev = doc.at_css(".mw-prevlink")
        {
          "current_offset" => params[:offset].to_i,
          "next" => nxt && "#{host}#{nxt['href']}",
          "previous" => prev && "#{host}#{prev['href']}"
        }.compact
      end
    end
  end
end
