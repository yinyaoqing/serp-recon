# frozen_string_literal: true

module SerpRecon
  class Error < StandardError
  end

  class UnknownEngineError < Error
  end

  # The fetch itself failed, or succeeded but returned something that is not
  # the page we asked for.
  class FetchError < Error
    attr_reader :status, :url

    def initialize(message, status: nil, url: nil)
      @status = status
      @url = url
      super(message)
    end
  end

  # The target returned HTTP 200 but the body is a JavaScript bootstrap shell
  # rather than rendered results. This is a *successful request* and a *failed
  # fetch*, and conflating the two is how scrapers end up silently returning
  # zero results forever.
  class JavaScriptGateError < FetchError; end

  # A required selector matched nothing. Raised loudly and by name, instead of
  # letting the parser return nil fields, because a parser that quietly returns
  # empty strings after a layout change is worse than one that crashes.
  class SelectorDriftError < Error
    attr_reader :engine, :selector

    def initialize(engine:, selector:, hint: nil)
      @engine = engine
      @selector = selector
      msg = "[#{engine}] required selector #{selector.inspect} matched nothing."
      msg << " #{hint}" if hint
      msg << " The page layout probably changed; re-record the fixture and update the parser."
      super(msg)
    end
  end
end
