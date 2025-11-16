# frozen_string_literal: true

require_relative 'metrics'

module Savant
  module Telemetry
    # Formats collected metrics for Prometheus scraping.
    module Exporter
      module_function

      def prometheus(snapshot = Savant::Telemetry::Metrics.snapshot)
        lines = []
        snapshot.each do |metric, entries|
          entries.each do |entry|
            if entry.key?(:value)
              lines << format_line(metric, entry[:labels], entry[:value])
            else
              labels = entry[:labels]
              lines << format_line("#{metric}_count", labels, entry[:count])
              lines << format_line("#{metric}_sum", labels, entry[:sum])
              lines << format_line("#{metric}_max", labels, entry[:max] || 0)
              lines << format_line("#{metric}_min", labels, entry[:min] || 0)
            end
          end
        end
        "#{lines.join("\n")}\n"
      end

      def format_line(metric, labels, value)
        label_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',')
        if label_str.empty?
          "#{metric} #{value}"
        else
          "#{metric}{#{label_str}} #{value}"
        end
      end
      private_class_method :format_line
    end
  end
end
