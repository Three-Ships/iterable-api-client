# typed: false

require 'spec_helper'

RSpec.describe Iterable::Config do
  subject(:conf) { described_class.new token: test_token }

  let(:test_token) { 'asdf123' }

  describe 'initialize' do
    it 'sets default host' do
      expect(conf.host).to eql(described_class::DEFAULT_HOST)
    end

    it 'sets default version' do
      expect(conf.version).to eql(described_class::DEFAULT_VERSION)
    end

    it 'sets default port' do
      expect(conf.port).to eql(described_class::DEFAULT_PORT)
    end

    it 'defaults token to nil' do
      expect(described_class.new.token).to be_nil
    end

    it 'defaults DNS cache TTL and retry count' do
      expect(conf.dns_cache_ttl).to eql(described_class::DEFAULT_DNS_CACHE_TTL)
      expect(conf.dns_retry_count).to eql(described_class::DEFAULT_DNS_RETRY_COUNT)
    end

    it 'allows DNS cache TTL and retry count to be overridden' do
      conf.dns_cache_ttl = 120
      conf.dns_retry_count = 5

      expect(conf.dns_cache_ttl).to eql(120)
      expect(conf.dns_retry_count).to eql(5)
    end

    it 'defaults the connection open timeout' do
      expect(conf.open_timeout).to eql(described_class::DEFAULT_OPEN_TIMEOUT)
    end

    it 'allows the connection open timeout to be overridden' do
      conf.open_timeout = 2

      expect(conf.open_timeout).to be(2)
    end

    context 'with a token' do
      it 'sets the token' do
        expect(conf.port).to eql(described_class::DEFAULT_PORT)
      end
    end
  end
end
