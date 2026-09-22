# frozen_string_literal: true

require "nokogiri"

module SerpRecon
  module Engines
    class Base
      # Subclasses declare:
      #   engine_name   - string used in search_parameters["engine"]
      #   results_key   - e.g. "organic_results", "book_results"
      #   required      - selectors that MUST match, or the layout has drifted
      #   live_fetch?   - false when a plain HTTP client cannot reach this target
      class << self
        attr_reader :engine_name, :results_key, :required_selectors

        def engine(name)          = @engine_name = name
        def results_key_is(key)   = @results_key = key
        def requires(*selectors)  = @required_selectors = selectors
        def live_fetch(bool)      = @live_fetch = bool
        def live_fetch?           = @live_fetch.nil? || @live_fetch

        def gated_reason(text = nil)
          @gated_reason = text if text
          @gated_reason
        end
      end

      attr_reader :params, :fetcher

      def initialize(fetcher: Fetcher.new, **params)
        @fetcher = fetcher
        @params = params
      end

      def call
        unless self.class.live_fetch?
          raise JavaScriptGateError.new(
            "#{self.class.engine_name}: live fetch is not supported. #{self.class.gated_reason} " \
            "Use SerpRecon.parse(engine:, html:) with a recorded fixture instead.",
            url: url
          )
        end

        parse(fetcher.get(url).body)
      end

      # Every engine must implement #url and #extract(doc).
      def url = raise(NotImplementedError)

      def parse(html)
        doc = Nokogiri::HTML(html)
        assert_selectors!(doc)
        data = extract(doc)
        envelope.build(**data)
      end

      private

      def envelope
        Envelope.new(
          engine: self.class.engine_name,
          params: params,
          results_key: self.class.results_key
        )
      end

      # The whole point: fail by name, at the boundary, before any field is read.
      #
      # A parser that returns {"title" => nil} after a redesign will happily run
      # in production for weeks. A parser that says
      #   [wikipedia] required selector "li.mw-search-result" matched nothing
      # is fixed the same afternoon.
      def assert_selectors!(doc)
        Array(self.class.required_selectors).each do |selector|
          next if doc.at_css(selector)

          raise SelectorDriftError.new(
            engine: self.class.engine_name,
            selector: selector,
            hint: hint_for(doc)
          )
        end
      end

      def hint_for(doc)
        title = doc.at_css("title")&.text.to_s.strip
        title.empty? ? nil : "Page title was #{title.inspect}."
      end

      def text_of(node, selector)
        node.at_css(selector)&.text&.strip
      end

      def squish(str)
        str.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
