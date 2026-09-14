# typed: false

require 'openssl'
require 'uri'

module Iterable
  # @!visibility private
  class Request
    extend T::Sig

    DEFAULT_OPTIONS = {
      use_ssl: true,
      verify_ssl: true,
      verify_mode: OpenSSL::SSL::VERIFY_PEER
    }.freeze

    CONNECT_FAILURES = [
      Net::OpenTimeout,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH
    ].freeze

    # Extra connect attempts using the next cached address (round-robin)
    # before dropping the entry. Avoids a CoreDNS round-trip that can
    # return the same ordered set and the same dead IP.
    CONNECT_CACHE_RETRIES = 1

    # getaddrinfo codes retried in {#with_dns_retries}. EAI_AGAIN is what
    # libc reports when a resolver query times out or its UDP packet is
    # dropped, which is the failure this cache exists to absorb. EAI_NONAME
    # and EAI_NODATA are authoritative answers; retrying them only delays a
    # failure that will not resolve itself.
    DNS_RETRYABLE_CODES = [Socket::EAI_AGAIN].freeze

    # Max sleep (seconds) before a DNS retry. Flat jitter only: libc has
    # already spent its own timeout budget by the time EAI_AGAIN surfaces,
    # and dropped packets clear on the next attempt rather than needing
    # progressive backoff.
    DNS_RETRY_JITTER_MAX = 0.1

    DEFAULT_HEADERS = {
      'accept' => 'application/json',
      'content-type' => 'application/json'
    }.freeze

    sig do
      params(
        config: Iterable::Config,
        path: String,
        params: Hash
      ).void
    end
    def initialize(config, path, params = {})
      @config = config
      @uri = build_uri(path, params)
      @net = nil
    end

    sig { params(headers: Hash).returns(Iterable::Response) }
    def get(headers = {})
      execute :get, {}, headers
    end

    sig { params(body: Hash, headers: Hash).returns(Iterable::Response) }
    def post(body = {}, headers = {})
      execute :post, body, headers
    end

    sig { params(body: Hash, headers: Hash).returns(Iterable::Response) }
    def put(body = {}, headers = {})
      execute :put, body, headers
    end

    sig { params(body: Hash, headers: Hash).returns(Iterable::Response) }
    def patch(body = {}, headers = {})
      execute :patch, body, headers
    end

    sig { params(body: Hash, headers: Hash).returns(Iterable::Response) }
    def delete(body = {}, headers = {})
      execute :delete, body, headers
    end

    private def execute(verb, body = {}, headers = {})
      http = connection(verb, body, headers)
      setup_http(http)
      transmit http
    end

    sig do
      params(
        verb: Symbol,
        body: Hash,
        headers: Hash
      ).returns(Net::HTTPRequest)
    end
    private def connection(verb, body = {}, headers = {})
      conn_headers = DEFAULT_HEADERS.dup.merge(headers)
      conn_headers['Api-Key'] = @config.token if @config.token
      req = Net::HTTP.const_get(verb.to_s.capitalize, false).new(@uri, conn_headers)
      req.body = JSON.dump(body)
      req
    end

    sig do
      params(
        http: T.any(Net::HTTP, Net::HTTP::Post, Net::HTTP::Get, Net::HTTP::Put, Net::HTTP::Patch, Net::HTTP::Delete)
      ).void
    end
    private def setup_http(http)
      DEFAULT_OPTIONS.dup.each do |option, value|
        setter = "#{option.to_sym}="
        http.send(setter, value) if http.respond_to?(setter)
      end
    end

    private def build_uri(path, params = {})
      uri = @config.uri
      uri.path += path
      uri.query = URI.encode_www_form(params) unless params.empty?
      uri
    end

    private def net_http
      http = Net::HTTP.new(@uri.hostname, @uri.port, nil, nil, nil, nil)
      http.ipaddr = DnsCache.fetch(@uri.hostname, @uri.port, @config.dns_cache_ttl)
      http
    end

    sig { params(req: Net::HTTPRequest).returns(Iterable::Response) }
    private def transmit(req)
      with_dns_retries do
        open_connection
        handle_response @net.request(req, nil, &:read_body)
      end
    end

    private def with_dns_retries
      attempts = 0
      begin
        yield
      rescue Socket::ResolutionError => e
        raise unless retryable_resolution_error?(e)
        raise if attempts >= @config.dns_retry_count

        attempts += 1
        reset_connection
        Kernel.sleep(rand * DNS_RETRY_JITTER_MAX)
        retry
      ensure
        close_connection
      end
    end

    # Errors raised by libc always carry an error_code. Anything constructed
    # elsewhere does not, and is retried rather than silently swallowed.
    private def retryable_resolution_error?(error)
      code = error.error_code
      code.nil? || DNS_RETRYABLE_CODES.include?(code)
    end

    private def open_connection
      attempts = 0
      begin
        @net ||= configured_net_http
        @net.start
      rescue *CONNECT_FAILURES
        reset_connection
        attempts += 1
        retry if attempts <= CONNECT_CACHE_RETRIES

        DnsCache.invalidate(@uri.hostname, @uri.port)
        raise
      end
    end

    private def reset_connection
      close_connection
      @net = nil
    end

    private def configured_net_http
      net_http.tap { |http| setup_http(http) }
    end

    private def close_connection
      @net.finish if @net && @net.started?
    end

    sig { params(response: Net::HTTPResponse).returns(Iterable::Response) }
    private def handle_response(response)
      redirected = response.is_a?(Net::HTTPRedirection) || response.code == '303'
      if redirected && response['location']
        Response.new Net::HTTP.get_response(uri_for_redirect(response))
      else
        Response.new response
      end
    end

    sig { params(response: Net::HTTPResponse).returns(URI) }
    private def uri_for_redirect(response)
      uri = @config.uri
      redirect_uri = URI(response['location'])
      uri.path = redirect_uri.path
      uri.query = redirect_uri.query
      uri
    end
  end
end
