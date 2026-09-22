# frozen_string_literal: true

require "net/http"
require "uri"
require "zlib"
require "stringio"

module SerpRecon
  # A deliberately small HTTP client. Everything here exists because a naive
  # Net::HTTP.get eventually bites you:
  #   - no timeout            -> a hung socket stalls the whole run
  #   - no retry              -> one transient 503 loses the batch
  #   - no backoff            -> retries make the rate limiting worse
  #   - no gzip handling      -> you parse binary and blame the parser
  #   - no JS-gate detection  -> you store a 200 that contains no results
  class Fetcher
    DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    # Markers that mean "HTTP 200, but this is a bootstrap shell, not content".
    JS_GATE_MARKERS = [
      "/httpservice/retry/enablejs",
      "Please click <a href=\"/httpservice/retry/enablejs",
      "enable JavaScript to continue",
      "Please enable JS"
    ].freeze

    attr_reader :user_agent, :timeout, :max_retries, :proxy

    def initialize(user_agent: DEFAULT_UA, timeout: 10, max_retries: 3, proxy: nil, sleeper: nil)
      @user_agent = user_agent
      @timeout = timeout
      @max_retries = max_retries
      @proxy = proxy # e.g. "http://user:pass@host:port"
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    # Returns a Response struct. Raises FetchError / JavaScriptGateError.
    def get(url, headers: {})
      attempt = 0
      begin
        attempt += 1
        response = perform(url, headers)
        check!(response, url)
        response
      rescue FetchError => e
        raise e if e.is_a?(JavaScriptGateError) # retrying will not help
        raise e if attempt > max_retries
        raise e if e.status && !retryable_status?(e.status)

        @sleeper.call(backoff_seconds(attempt))
        retry
      end
    end

    # Fetch without raising, for reachability probing. Never raises on HTTP status.
    def probe(url, headers: {})
      response = perform(url, headers)
      [response, gate_marker(response.body)]
    rescue StandardError => e
      [Response.new(status: nil, body: "", headers: {}, url: url, error: e.class.name), nil]
    end

    Response = Struct.new(:status, :body, :headers, :url, :error, keyword_init: true) do
      def ok? = status == 200
      def bytes = body.to_s.bytesize
    end

    private

    def retryable_status?(status)
      status >= 500 || status == 429 || status == 408
    end

    # 1s, 2s, 4s ... with a little jitter so parallel workers do not resonate.
    def backoff_seconds(attempt)
      (2**(attempt - 1)) + (rand * 0.3)
    end

    def perform(url, headers)
      uri = URI.parse(url)
      http = build_http(uri)
      request = Net::HTTP::Get.new(uri)
      default_headers.merge(headers).each { |k, v| request[k] = v }
      raw = http.request(request)
      Response.new(
        status: raw.code.to_i,
        body: decode(raw),
        headers: raw.each_header.to_h,
        url: url
      )
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise FetchError.new("timeout after #{timeout}s (#{e.class})", url: url)
    rescue SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED => e
      raise FetchError.new("connection failed: #{e.class}: #{e.message}", url: url)
    end

    def build_http(uri)
      http =
        if proxy
          p = URI.parse(proxy)
          Net::HTTP.new(uri.host, uri.port, p.host, p.port, p.user, p.password)
        else
          Net::HTTP.new(uri.host, uri.port)
        end
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http
    end

    def default_headers
      {
        "User-Agent" => user_agent,
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9",
        "Accept-Encoding" => "gzip, deflate"
      }
    end

    def decode(raw)
      body = raw.body.to_s
      return body unless raw["content-encoding"].to_s.include?("gzip")

      Zlib::GzipReader.new(StringIO.new(body)).read
    rescue Zlib::Error
      body
    end

    def check!(response, url)
      raise FetchError.new("HTTP #{response.status}", status: response.status, url: url) unless response.ok?

      marker = gate_marker(response.body)
      return unless marker

      raise JavaScriptGateError.new(
        "HTTP 200 but the body is a JavaScript bootstrap shell (matched #{marker.inspect}). " \
        "This target needs a real browser, not an HTTP client.",
        status: 200, url: url
      )
    end

    def gate_marker(body)
      JS_GATE_MARKERS.find { |m| body.to_s.include?(m) }
    end
  end
end
