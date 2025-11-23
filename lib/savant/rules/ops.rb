#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

module Savant
  module Rules
    class Ops
      def initialize(root: nil)
        @base = root || default_base_path
        @data_path = File.join(@base, 'lib', 'savant', 'rules', 'rules.yml')
      end

      def list(filter: nil)
        rows = load_catalog.map do |r|
          { name: r['name'], title: r['title'], version: r['version'], summary: r['summary'], tags: r['tags'] }
        end
        if filter && !filter.to_s.strip.empty?
          q = filter.to_s.downcase
          rows = rows.select { |h| [h[:name], h[:title], h[:summary], Array(h[:tags]).join(' ')].any? { |v| v.to_s.downcase.include?(q) } }
        end
        { rules: rows }
      end

      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?
        row = load_catalog.find { |r| r['name'] == key }
        raise 'not_found' unless row
        {
          name: row['name'], title: row['title'], version: row['version'], summary: row['summary'],
          tags: row['tags'], rules_md: row['rules_md'], notes: row['notes']
        }
      end

      private

      def default_base_path
        (ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?) ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__)
      end

      def load_catalog
        raise 'load_error: rules.yml not found' unless File.file?(@data_path)
        data = YAML.safe_load(File.read(@data_path))
        rows = data.is_a?(Array) ? data : []
        rows.each do |r|
          %w[name title version summary rules_md].each do |req|
            raise "invalid_data: missing #{req}" unless r.key?(req) && !r[req].to_s.strip.empty?
          end
        end
        rows
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end
    end
  end
end

