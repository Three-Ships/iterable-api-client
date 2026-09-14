# typed: false

require 'spec_helper'

RSpec.describe Iterable::Request do
  subject(:request) { described_class.new(config, '/test-path') }

  let(:test_token) { 'asdf-1234-qwer-5678' }
  let(:config) { Iterable::Config.new(token: test_token) }
  let(:test_net_http) { instance_double(Net::HTTP) }
  let(:test_request) { instance_double(Net::HTTP::Get) }
  let(:test_net_resp) { instance_double(Net::HTTPResponse) }
  let(:test_response) { instance_double(Iterable::Response) }
  let(:test_uri) { URI('https://api.iterable.com/api/test-path') }
  let(:request_headers) { described_class::DEFAULT_HEADERS.merge('Api-Key' => test_token) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(test_net_http)
    allow(Iterable::DnsCache).to receive(:fetch).and_return('192.0.2.1')
    allow(net_http_class).to receive(:new).and_return(test_request)
    allow(test_net_http).to receive(:ipaddr=)
    allow(test_net_http).to receive(:start).and_return(test_net_http)
    allow(test_net_http).to receive(:started?).and_return(false)
    allow(test_request).to receive(:body=)
    allow(test_net_http).to receive(:request).and_return(test_net_resp)
    allow(test_net_resp).to receive(:code)
    allow(test_net_resp).to receive(:body)
  end

  describe 'get' do
    let(:net_http_class) { Net::HTTP::Get }
    let(:http_verb) { :get }

    before { request.get }

    it 'uses the resolved IP while preserving the hostname for TLS', :aggregate_failures do
      expect(Net::HTTP).to have_received(:new).with('api.iterable.com', 443, nil, nil, nil, nil)
      expect(Iterable::DnsCache).to have_received(:fetch).with('api.iterable.com', 443, config.dns_cache_ttl)
      expect(test_net_http).to have_received(:ipaddr=).with('192.0.2.1')
      expect(net_http_class).to have_received(:new).with(test_uri, request_headers)
      expect(test_net_http).to have_received(:request).with(test_request, nil, &:read_body)
    end
  end

  describe 'post' do
    let(:net_http_class) { Net::HTTP::Post }
    let(:http_verb) { :post }

    before { request.post }

    it 'calls http request correctly', :aggregate_failures do
      expect(Net::HTTP).to have_received(:new).with(config.uri.hostname, config.uri.port, nil, nil, nil, nil)
      expect(net_http_class).to have_received(:new).with(test_uri, request_headers)
      expect(test_net_http).to have_received(:request).with(test_request, nil, &:read_body)
    end
  end

  describe 'put' do
    let(:net_http_class) { Net::HTTP::Put }
    let(:http_verb) { :put }

    before { request.put }

    it 'calls http request correctly', :aggregate_failures do
      expect(Net::HTTP).to have_received(:new).with(config.uri.hostname, config.uri.port, nil, nil, nil, nil)
      expect(net_http_class).to have_received(:new).with(test_uri, request_headers)
      expect(test_net_http).to have_received(:request).with(test_request, nil, &:read_body)
    end
  end

  describe 'patch' do
    let(:net_http_class) { Net::HTTP::Patch }
    let(:http_verb) { :patch }

    before { request.patch }

    it 'calls http request correctly', :aggregate_failures do
      expect(Net::HTTP).to have_received(:new).with(config.uri.hostname, config.uri.port, nil, nil, nil, nil)
      expect(net_http_class).to have_received(:new).with(test_uri, request_headers)
      expect(test_net_http).to have_received(:request).with(test_request, nil, &:read_body)
    end
  end

  describe 'delete' do
    let(:net_http_class) { Net::HTTP::Delete }
    let(:http_verb) { :delete }

    before { request.delete }

    it 'calls http request correctly', :aggregate_failures do
      expect(Net::HTTP).to have_received(:new).with(config.uri.hostname, config.uri.port, nil, nil, nil, nil)
      expect(net_http_class).to have_received(:new).with(test_uri, request_headers)
      expect(test_net_http).to have_received(:request).with(test_request, nil, &:read_body)
    end
  end

  describe 'connect failures' do
    let(:net_http_class) { Net::HTTP::Get }
    let(:retried_net_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(test_net_http, retried_net_http)
      allow(Iterable::DnsCache).to receive(:fetch).and_return('192.0.2.1', '192.0.2.2')
      allow(Iterable::DnsCache).to receive(:invalidate)
      allow(test_net_http).to receive(:start).and_raise(Net::OpenTimeout)
      allow(retried_net_http).to receive(:ipaddr=)
      allow(retried_net_http).to receive(:started?).and_return(false)
    end

    it 'retries the next cached IP without invalidating' do
      allow(retried_net_http).to receive(:start).and_return(retried_net_http)

      request.send(:open_connection)

      expect(Iterable::DnsCache).not_to have_received(:invalidate)
      expect(Iterable::DnsCache).to have_received(:fetch).with('api.iterable.com', 443, config.dns_cache_ttl).twice
      expect(retried_net_http).to have_received(:ipaddr=).with('192.0.2.2')
    end

    it 'invalidates after the cached retry also fails' do
      allow(retried_net_http).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect { request.send(:open_connection) }.to raise_error(Errno::ECONNREFUSED)

      expect(Iterable::DnsCache).to have_received(:invalidate).with('api.iterable.com', 443).once
      expect(Iterable::DnsCache).to have_received(:fetch).twice
    end
  end

  describe 'DNS resolution failures' do
    let(:net_http_class) { Net::HTTP::Get }

    def resolution_error(code)
      Socket::ResolutionError.new('getaddrinfo failure').tap do |error|
        allow(error).to receive(:error_code).and_return(code)
      end
    end

    before do
      allow(Kernel).to receive(:sleep)
    end

    it 'retries EAI_AGAIN up to the configured count and then re-raises' do
      config.dns_retry_count = 2
      allow(Iterable::DnsCache).to receive(:fetch).and_raise(resolution_error(Socket::EAI_AGAIN))

      expect { request.get }.to raise_error(Socket::ResolutionError)
      expect(Iterable::DnsCache).to have_received(:fetch).exactly(3).times
      expect(Kernel).to have_received(:sleep).twice
    end

    it 'does not retry EAI_NONAME, which is an authoritative answer' do
      allow(Iterable::DnsCache).to receive(:fetch).and_raise(resolution_error(Socket::EAI_NONAME))

      expect { request.get }.to raise_error(Socket::ResolutionError)
      expect(Iterable::DnsCache).to have_received(:fetch).once
      expect(Kernel).not_to have_received(:sleep)
    end

    it 'retries errors that carry no error_code' do
      config.dns_retry_count = 1
      allow(Iterable::DnsCache).to receive(:fetch).and_raise(resolution_error(nil))

      expect { request.get }.to raise_error(Socket::ResolutionError)
      expect(Iterable::DnsCache).to have_received(:fetch).twice
    end

    it 'does not retry non-DNS SocketErrors' do
      error = SocketError.new('connection failed')
      allow(Iterable::DnsCache).to receive(:fetch).and_raise(error)

      expect { request.get }.to raise_error(error)
      expect(Iterable::DnsCache).to have_received(:fetch).once
      expect(Kernel).not_to have_received(:sleep)
    end
  end
end
