# typed: true

module Iterable
  ##
  # Config provides a class to configre the API calls when interacting with
  # REST endpoints
  #
  # @example Creating a config object
  #   Iterable::Config.new token: 'secret-token'
  class Config
    extend T::Sig

    DEFAULT_VERSION = '1.8'.freeze
    DEFAULT_HOST = 'https://api.iterable.com'.freeze
    DEFAULT_URI = "#{DEFAULT_HOST}/api".freeze
    DEFAULT_PORT = 443
    # Seconds to retain resolved A records before re-querying DNS.
    DEFAULT_DNS_CACHE_TTL = 60
    # Extra attempts after a retryable Socket::ResolutionError (EAI_AGAIN).
    DEFAULT_DNS_RETRY_COUNT = 3
    # Seconds allowed for the TCP and TLS handshakes combined.
    DEFAULT_OPEN_TIMEOUT = 5

    attr_accessor :token
    # @return [Integer] seconds to cache resolved IPv4 addresses
    attr_accessor :dns_cache_ttl
    # @return [Integer] retries after a transient DNS failure
    attr_accessor :dns_retry_count
    # @return [Integer] seconds allowed to open a connection (TCP + TLS)
    attr_accessor :open_timeout
    attr_reader :host, :port, :version

    ##
    #
    # initialize a new [Iterable::Config] object for requests
    #
    # @param token [String] Iterable API token
    # @return [Iterable::Config]
    sig { params(token: T.nilable(String)).void }
    def initialize(token: nil)
      @host = DEFAULT_HOST
      @port = DEFAULT_PORT
      @version = DEFAULT_VERSION
      @token = token
      @dns_cache_ttl = DEFAULT_DNS_CACHE_TTL
      @dns_retry_count = DEFAULT_DNS_RETRY_COUNT
      @open_timeout = DEFAULT_OPEN_TIMEOUT
    end

    ##
    #
    # Creates a [URI] for the API host
    #
    # @return [URI] API URI object
    sig { returns(URI) }
    def uri
      URI.parse("#{@host || DEFAULT_HOST}:#{@port || DEFAULT_PORT}/api")
    end
  end
end
