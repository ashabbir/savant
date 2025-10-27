# frozen_string_literal: true

begin
  require 'simplecov'
  SimpleCov.start do
    enable_coverage :branch
    add_filter '/spec/'
  end
rescue LoadError
  # Fallback: builtin Coverage for total percent
  begin
    require 'coverage'
    Coverage.start
    at_exit do
      result = Coverage.result
      files = result.keys.reject { |p| p.include?('/spec/') }
      covered = 0
      total = 0
      files.each do |f|
        arr = result[f]
        next unless arr.is_a?(Array)

        arr.each do |cnt|
          next if cnt.nil?

          total += 1
          covered += 1 if cnt.to_i > 0
        end
      end
      pct = total > 0 ? (covered.to_f * 100.0 / total).round(2) : 0.0
      puts "Coverage (builtin): #{pct}% (#{covered}/#{total})"
    end
  rescue LoadError
    # ignore
  end
end

require 'rspec'
require 'json'

# Load library under test
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'savant/logger'
require 'savant/middleware/logging'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
# !/usr/bin/env ruby
# frozen_string_literal: true
