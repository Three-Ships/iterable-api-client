# typed: false

require 'spec_helper'

RSpec.describe Iterable::DnsCache do
  let(:hostname) { 'api.iterable.test' }
  let(:port) { 443 }

  before { described_class.reset! }

  def address(ip)
    instance_double(Addrinfo, ip_address: ip)
  end

  it 'resolves a trailing-dot FQDN over IPv4 TCP' do
    expect(Addrinfo).to receive(:getaddrinfo)
      .with('api.iterable.test.', port, :INET, :STREAM)
      .and_return([address('192.0.2.1')])

    expect(described_class.fetch(hostname, port, 60)).to eql('192.0.2.1')
  end

  it 'uses cached addresses until the TTL expires' do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([address('192.0.2.2')])

    2.times { described_class.fetch('ttl.iterable.test', port, 60) }
    described_class.fetch('expired.iterable.test', port, 0)
    described_class.fetch('expired.iterable.test', port, 0)

    expect(Addrinfo).to have_received(:getaddrinfo).with('ttl.iterable.test.', port, :INET, :STREAM).once
    expect(Addrinfo).to have_received(:getaddrinfo).with('expired.iterable.test.', port, :INET, :STREAM).twice
  end

  it 'rotates cached addresses' do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([address('192.0.2.3'), address('192.0.2.4')])

    addresses = 3.times.map { described_class.fetch('round-robin.iterable.test', port, 60) }

    expect(addresses).to eql(%w[192.0.2.3 192.0.2.4 192.0.2.3])
  end

  it 'resolves again after invalidation' do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([address('192.0.2.5')])

    described_class.fetch('invalidate.iterable.test', port, 60)
    described_class.invalidate('invalidate.iterable.test', port)
    described_class.fetch('invalidate.iterable.test', port, 60)

    expect(Addrinfo).to have_received(:getaddrinfo).twice
  end

  it 'does not append a second trailing dot when the hostname is already FQDN' do
    expect(Addrinfo).to receive(:getaddrinfo)
      .with('api.iterable.test.', port, :INET, :STREAM)
      .and_return([address('192.0.2.7')])

    expect(described_class.fetch('api.iterable.test.', port, 60)).to eql('192.0.2.7')
  end

  it 'raises SocketError when getaddrinfo returns no addresses' do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([])

    expect { described_class.fetch(hostname, port, 60) }
      .to raise_error(SocketError, 'no IPv4 addresses for api.iterable.test.')
  end

  it 'caches addresses per hostname and port' do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([address('192.0.2.8')])

    described_class.fetch(hostname, 443, 60)
    described_class.fetch(hostname, 8443, 60)

    expect(Addrinfo).to have_received(:getaddrinfo).twice
  end

  it 'singleflights concurrent cache misses' do
    allow(Addrinfo).to receive(:getaddrinfo) do
      sleep 0.05
      [address('192.0.2.6')]
    end

    addresses = 5.times.map do
      Thread.new { described_class.fetch('singleflight.iterable.test', port, 60) }
    end.map(&:value)

    expect(addresses).to all(eql('192.0.2.6'))
    expect(Addrinfo).to have_received(:getaddrinfo).once
  end
end
