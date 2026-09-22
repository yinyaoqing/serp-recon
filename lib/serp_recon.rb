# frozen_string_literal: true

require "serp_recon/version"
require "serp_recon/errors"
require "serp_recon/fetcher"
require "serp_recon/envelope"
require "serp_recon/probe"
require "serp_recon/engines/base"
require "serp_recon/engines/wikipedia"
require "serp_recon/engines/google_books"

# A small toolkit for two questions that always come before a SERP parser:
#   1. Can this target actually be fetched by a plain HTTP client?  -> Probe
#   2. Given the HTML, can it be parsed into a stable contract?     -> Engines
module SerpRecon
  ENGINES = {
    "wikipedia" => Engines::Wikipedia,
    "google_books" => Engines::GoogleBooks
  }.freeze

  module_function

  def engine(name)
    ENGINES.fetch(name) do
      raise UnknownEngineError, "unknown engine #{name.inspect} (have: #{ENGINES.keys.join(', ')})"
    end
  end

  # Fetch + parse, returning the SerpApi-shaped envelope as a Hash.
  def search(engine:, **params)
    engine(engine).new(**params).call
  end

  # Parse HTML you already have. Used by the fixture specs, and the only
  # entry point that works for engines whose live fetch is gated.
  def parse(engine:, html:, **params)
    engine(engine).new(**params).parse(html)
  end
end
