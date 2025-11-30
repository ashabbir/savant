# frozen_string_literal: true

module Savant
  module Logging
    # Thread-safe counters + distributions that back the framework metrics.
    class Metrics
      class << self
        def increment(name, labels = {}, by: 1, **kw_labels)
          merged = merge_labels(labels, kw_labels)
          mutate_counter(name, merged) { |entry| entry[:value] += by }
        end

        def observe(name, value, labels = {}, **kw_labels)
          merged = merge_labels(labels, kw_labels)
          value = value.to_f
          mutate_distribution(name, merged) do |entry|
            entry[:count] += 1
            entry[:sum] += value
            entry[:min] = value if entry[:min].nil? || value < entry[:min]
            entry[:max] = value if entry[:max].nil? || value > entry[:max]
          end
        end

        def snapshot
          mutex.synchronize do
            {
              'tool_invocations_total' => clone_entries(@counters['tool_invocations_total']),
              'tool_errors_total' => clone_entries(@counters['tool_errors_total']),
              'tool_duration_seconds' => clone_entries(@distributions['tool_duration_seconds'])
            }.delete_if { |_k, v| v.nil? || v.empty? }
          end
        end

        def reset!
          mutex.synchronize do
            @counters = Hash.new { |h, k| h[k] = {} }
            @distributions = Hash.new { |h, k| h[k] = {} }
          end
        end

        private

        def mutex
          @mutex ||= Mutex.new
        end

        def clone_entries(collection)
          return [] unless collection

          collection.values.map { |entry| Marshal.load(Marshal.dump(entry)) }
        end

        def mutate_counter(name, labels)
          mutex.synchronize do
            entry = (@counters[name][hash_key(labels)] ||= { labels: symbolize_labels(labels), value: 0 })
            yield(entry)
            entry
          end
        end

        def mutate_distribution(name, labels)
          mutex.synchronize do
            entry = (@distributions[name][hash_key(labels)] ||= { labels: symbolize_labels(labels), count: 0,
                                                                  sum: 0.0, min: nil, max: nil })
            yield(entry)
            entry
          end
        end

        def symbolize_labels(labels)
          (labels || {}).transform_keys(&:to_sym)
        end

        def hash_key(labels)
          symbolize_labels(labels).sort_by { |k, _| k.to_s }.map { |k, v| [k, v] }.flatten.join(':')
        end

        def merge_labels(hash_labels, kw_labels)
          (hash_labels || {}).merge(kw_labels.transform_keys(&:to_sym))
        end
      end

      reset!
    end
  end
end
