# frozen_string_literal: true

require "cgi"
require "json"

module SerpRecon
  module Engines
    # Addresses serpapi/public-roadmap#63 ("[New API] Add Google Books API",
    # status: freezer, opened 2022-03-10).
    #
    # Deliberately NOT a scraper. The recon (docs/recon-2026-09-22.md) found
    # that google.com/search?tbm=bks returns HTTP 200 with a JavaScript
    # bootstrap shell and zero results for any plain HTTP client, while Google
    # publishes a free, documented JSON API covering the same corpus. When a
    # first-party API exists, the engineering problem is normalisation, not
    # access -- and the cheapest correct answer to #63 is a normaliser.
    #
    # The HTML path is kept as a documented dead end rather than deleted,
    # because "we checked, here is why not" is the useful artifact.
    #
    # FIELD MAPPING STATUS: written against Google's published Books API v1
    # schema. It has NOT been verified against a live response, because the
    # keyless anonymous quota was exhausted at the time of writing (HTTP 429).
    # Record a fixture with your own key and the specs will check the mapping
    # for you -- including fields this mapper silently drops.
    #   ruby bin/record_fixture.rb google_books "ruby programming" $GOOGLE_BOOKS_KEY
    class GoogleBooks < Base
      engine "google_books"
      results_key_is "book_results"
      live_fetch true

      API = "https://www.googleapis.com/books/v1/volumes"
      HTML_DEAD_END = "https://www.google.com/search?tbm=bks"

      # Every volumeInfo key this mapper reads. The fixture spec cross-checks a
      # recorded response against this list and reports anything unmapped, so
      # the unverified mapping above becomes a test failure rather than a
      # silent omission.
      MAPPED_VOLUME_KEYS = %w[
        title subtitle authors publisher publishedDate description
        industryIdentifiers pageCount categories averageRating ratingsCount
        imageLinks language previewLink infoLink canonicalVolumeLink
      ].freeze

      def initialize(q:, limit: 10, offset: 0, api_key: ENV.fetch("GOOGLE_BOOKS_KEY", nil), **rest)
        super(q: q, limit: limit, offset: offset, **rest)
        @api_key = api_key
      end

      def url
        query = {
          q: params[:q], maxResults: params[:limit], startIndex: params[:offset]
        }
        query[:key] = @api_key if @api_key
        "#{API}?#{query.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')}"
      end

      # JSON, not HTML -- so this engine overrides parse rather than extract.
      def parse(body)
        payload = body.is_a?(Hash) ? body : JSON.parse(body)

        if payload["error"]
          raise FetchError.new(
            "Books API error #{payload['error']['code']}: #{payload['error']['message']}",
            status: payload["error"]["code"], url: API
          )
        end

        envelope.build(
          results: Array(payload["items"]).map.with_index { |item, i| volume(item, i) },
          total_results: payload["totalItems"],
          pagination: { "current_offset" => params[:offset].to_i, "per_page" => params[:limit].to_i }
        )
      end

      private

      def extract(_doc) = raise(NotImplementedError, "google_books consumes JSON, not HTML")

      def volume(item, index)
        info = item["volumeInfo"] || {}
        {
          "position" => index + 1 + params[:offset].to_i,
          "volume_id" => item["id"],
          "title" => info["title"],
          "subtitle" => info["subtitle"],
          "authors" => info["authors"],
          "publisher" => info["publisher"],
          "published_date" => info["publishedDate"],
          "page_count" => info["pageCount"],
          "categories" => info["categories"],
          "language" => info["language"],
          "rating" => info["averageRating"],
          "reviews" => info["ratingsCount"],
          "snippet" => info["description"],
          "isbn" => isbns(info["industryIdentifiers"]),
          "thumbnail" => info.dig("imageLinks", "thumbnail"),
          "link" => info["canonicalVolumeLink"] || info["infoLink"],
          "preview_link" => info["previewLink"]
        }.compact
      end

      # [{type: "ISBN_13", identifier: "..."}] -> {"isbn_13" => "..."}
      def isbns(identifiers)
        return nil if identifiers.nil? || identifiers.empty?

        identifiers.to_h { |id| [id["type"].to_s.downcase, id["identifier"]] }
      end
    end
  end
end
