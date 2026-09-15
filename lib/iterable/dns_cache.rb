# typed: false

require 'socket'

module Iterable
  # Process-wide IPv4 cache for Iterable API hosts.
  #
  # Resolves with a trailing-dot FQDN so Kubernetes ndots:5 does not emit
  # extra search-domain queries. Entries are keyed by hostname and port,
  # expire after the caller-supplied TTL, and rotate round-robin from a
  # randomly seeded offset.
  # Concurrent misses for the same key singleflight on a ConditionVariable.
  # {invalidate} drops an entry so the next fetch re-resolves (e.g. after a
  # TCP connect failure).
  #
  # @!visibility private
  class DnsCache
    class << self
      def fetch(hostname, port, ttl)
        key = cache_key(hostname, port)
        entry = nil

        mutex.synchronize do
          loop do
            entry = cache[key]
            return next_address(entry) if fresh?(entry)

            if entry && entry[:resolving]
              entry[:condition].wait(mutex)
            else
              entry ||= { condition: ConditionVariable.new }
              entry[:resolving] = true
              cache[key] = entry
              break
            end
          end
        end

        addresses = resolve(hostname, port)
        mutex.synchronize do
          entry[:addresses] = addresses
          entry[:expires_at] = monotonic_time + ttl
          # Seeded rather than zeroed so replicas resolving the same host do
          # not all open their first connection to addresses[0]. Zeroing made
          # a dead first address a guaranteed hit at the start of every TTL
          # window for every process, instead of a one-in-N chance.
          entry[:index] = rand(addresses.length)
          entry[:resolving] = false
          entry[:condition].broadcast
          next_address(entry)
        end
      rescue StandardError
        mutex.synchronize do
          if entry
            cache.delete(key)
            entry[:resolving] = false
            entry[:condition].broadcast
          end
        end
        raise
      end

      def invalidate(hostname, port)
        mutex.synchronize { cache.delete(cache_key(hostname, port)) }
      end

      def reset!
        mutex.synchronize { cache.clear }
      end

      private

      def resolve(hostname, port)
        fqdn = hostname.end_with?('.') ? hostname : "#{hostname}."
        addresses = Addrinfo.getaddrinfo(fqdn, port, :INET, :STREAM).map(&:ip_address).uniq
        raise SocketError, "no IPv4 addresses for #{fqdn}" if addresses.empty?

        addresses
      end

      def fresh?(entry)
        entry && entry[:addresses] && entry[:expires_at] > monotonic_time
      end

      def next_address(entry)
        addresses = entry[:addresses]
        raise SocketError, 'no IPv4 addresses in cache entry' if addresses.nil? || addresses.empty?

        address = addresses[entry[:index] % addresses.length]
        entry[:index] += 1
        address
      end

      def cache_key(hostname, port)
        [hostname, port]
      end

      def cache
        @cache ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
