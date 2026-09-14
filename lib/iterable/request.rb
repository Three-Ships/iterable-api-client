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
      @net = net_http
      setup_http(@net)
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
      open_connection
      response = @net.request(req, nil, &:read_body)
      handle_response response
    ensure
      @net.finish if @net.started?
    end

    private def open_connection(refreshed = false)
      @net.start
    rescue *CONNECT_FAILURES
      raise if refreshed

      DnsCache.invalidate(@uri.hostname)
      @net = net_http
      setup_http(@net)
      open_connection(true)
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
