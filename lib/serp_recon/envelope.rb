# frozen_string_literal: true

require "securerandom"
require "time"

module SerpRecon
  # The response shape. Deliberately mirrors SerpApi's published envelope
  # (search_metadata / search_parameters / search_information / <results> /
  # pagination) so that a consumer written against their Google APIs can read
  # this without a translation layer.
  class Envelope
    def initialize(engine:, params:, results_key:)
      @engine = engine
      @params = params
      @results_key = results_key
      @started_at = Time.now
      @id = SecureRandom.hex(8)
    end

    def build(results:, total_results: nil, pagination: nil, status: "Success")
      finished = Time.now
      {
        "search_metadata" => {
          "id" => @id,
          "status" => status,
          "created_at" => @started_at.utc.iso8601,
          "processed_at" => finished.utc.iso8601,
          "total_time_taken" => (finished - @started_at).round(3)
        },
        "search_parameters" => { "engine" => @engine }.merge(stringify(@params)),
        "search_information" => {
          "total_results" => total_results
        }.compact,
        @results_key => results,
        "pagination" => pagination
      }.compact
    end

    private

    def stringify(hash)
      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v unless v.nil? }
    end
  end
end
