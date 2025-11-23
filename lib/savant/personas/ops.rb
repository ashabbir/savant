#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

module Savant
  module Personas
    # Ops for Personas engine: loads YAML catalog and implements list/get.
    class Ops
      def initialize(root: nil)
        @base = root || default_base_path
        @data_path = File.join(@base, 'lib', 'savant', 'personas', 'personas.yml')
      end

      # List personas with optional filter on name|title|tags|summary
      # @return [Hash] { personas: [{ name, title, version, summary, tags? }] }
      def list(filter: nil)
        rows = load_catalog.map do |p|
          {
            name: p['name'],
            title: p['title'],
            version: p['version'],
            summary: p['summary'],
            tags: p['tags']
          }
        end
        if filter && !filter.to_s.strip.empty?
          q = filter.to_s.downcase
          rows = rows.select do |r|
            [r[:name], r[:title], r[:summary], Array(r[:tags]).join(' ')].compact.any? { |v| v.to_s.downcase.include?(q) }
          end
        end
        { personas: rows }
      end

      # Get a persona by name
      # @return [Hash] or raises 'NOT_FOUND'
      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?
        row = load_catalog.find { |p| p['name'] == key }
        raise 'not_found' unless row
        {
          name: row['name'],
          title: row['title'],
          version: row['version'],
          summary: row['summary'],
          tags: row['tags'],
          prompt_md: row['prompt_md'],
          notes: row['notes']
        }
      end

      private

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../..', __dir__)
        end
      end

      def load_catalog
        raise 'load_error: personas.yml not found' unless File.file?(@data_path)
        data = YAML.safe_load(File.read(@data_path))
        rows = data.is_a?(Array) ? data : []
        rows.each do |p|
          %w[name title version summary prompt_md].each do |req|
            raise "invalid_data: missing #{req}" unless p.key?(req) && !p[req].to_s.strip.empty?
          end
        end
        rows
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      rescue StandardError => e
        raise e
      end
    end
  end
end

