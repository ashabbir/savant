#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

module Savant
  module Drivers
    # Ops for Drivers engine: loads YAML catalog of driver prompt templates.
    class Ops
      def initialize(root: nil)
        @base = root || default_base_path
        @data_path = File.join(@base, 'lib', 'savant', 'engines', 'drivers', 'drivers.yml')
      end

      # One-time migration: import Think prompts (prompts.yml + markdown files)
      # into Drivers catalog if Drivers catalog is empty.
      # Safe to call repeatedly; no-ops when drivers already present or Think
      # prompts are missing.
      def migrate_from_think_prompts
        begin
          existing = load_catalog rescue []
          return false unless existing.is_a?(Array) && existing.empty?

          think_root = File.join(@base, 'lib', 'savant', 'engines', 'think')
          reg_path = File.join(think_root, 'prompts.yml')
          return false unless File.file?(reg_path)

          reg = YAML.safe_load(File.read(reg_path)) || {}
          versions = reg['versions'] || {}
          return false unless versions.is_a?(Hash) && !versions.empty?

          rows = []
          versions.each do |ver, rel|
            next unless rel.is_a?(String)
            path = File.join(think_root, rel)
            next unless File.file?(path)
            md = File.read(path)
            # Summary = first non-empty line without markdown header markers
            summary = begin
              first_line = md.lines.find { |l| !l.strip.empty? }&.strip || ver.to_s
              first_line.sub(/^#+\s*/, '')[0, 160]
            rescue StandardError
              ver.to_s
            end
            rows << {
              'name' => ver.to_s,
              'version' => 1,
              'summary' => summary,
              'prompt_md' => md,
              'tags' => ['think']
            }
          end
          return false if rows.empty?

          write_catalog(rows)
          true
        rescue StandardError
          false
        end
      end

      # List drivers with optional filter on name|tags|summary
      # @return [Hash] { drivers: [{ name, version, summary, tags? }] }
      def list(filter: nil)
        rows = load_catalog.map do |p|
          {
            name: p['name'],
            version: p['version'],
            summary: p['summary'],
            tags: p['tags']
          }
        end
        if filter && !filter.to_s.strip.empty?
          q = filter.to_s.downcase
          rows = rows.select do |r|
            [r[:name], r[:summary], Array(r[:tags]).join(' ')].compact.any? { |v| v.to_s.downcase.include?(q) }
          end
        end
        { drivers: rows }
      end

      # Get a driver by name
      # @return [Hash] or raises 'NOT_FOUND'
      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?

        row = load_catalog.find { |p| p['name'] == key }
        raise 'not_found' unless row

        {
          name: row['name'],
          version: row['version'],
          summary: row['summary'],
          tags: row['tags'],
          prompt_md: row['prompt_md'],
          notes: row['notes']
        }
      end

      # Read a single driver as YAML text
      def read_driver_yaml(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        row = rows.find { |p| p['name'] == n }
        raise 'not_found' unless row

        { driver_yaml: YAML.dump(row) }
      end

      # Overwrite a single driver from YAML
      def write_driver_yaml(name:, yaml:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        data = safe_yaml_load(yaml)
        validate_entry!(data)
        rows = load_catalog
        idx = rows.index { |p| p['name'] == n }
        raise 'not_found' unless idx

        rows[idx] = data
        write_catalog(rows)
        { ok: true, name: n }
      end

      # Read entire catalog
      def catalog_read
        rows = load_catalog
        { catalog_yaml: YAML.dump(rows) }
      end

      # Overwrite catalog with YAML array
      def catalog_write(yaml:)
        rows = safe_yaml_load(yaml)
        raise 'invalid_yaml: expected an array' unless rows.is_a?(Array)

        rows.each { |p| validate_entry!(p) }
        write_catalog(rows)
        { ok: true, count: rows.length }
      end

      # CRUD
      def create(name:, summary:, prompt_md:, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        raise 'conflict: name already exists' if rows.any? { |p| p['name'] == n }

        entry = {
          'name' => n,
          'version' => 1,
          'summary' => summary.to_s,
          'prompt_md' => prompt_md.to_s,
          'tags' => Array(tags).map(&:to_s),
          'notes' => notes
        }
        validate_entry!(entry)
        rows << entry
        write_catalog(rows)
        { ok: true, name: n }
      end

      def update(name:, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        idx = rows.index { |p| p['name'] == n }
        raise 'not_found' unless idx

        row = rows[idx]
        row['summary'] = summary unless summary.nil?
        row['prompt_md'] = prompt_md unless prompt_md.nil?
        row['tags'] = Array(tags).map(&:to_s) unless tags.nil?
        row['notes'] = notes unless notes.nil?
        row['version'] = (row['version'].to_i <= 0 ? 1 : row['version'].to_i) + 1
        validate_entry!(row)
        rows[idx] = row
        write_catalog(rows)
        { ok: true, name: n }
      end

      def delete(name:)
        n = normalize_name(name)
        rows = load_catalog
        before = rows.length
        rows = rows.reject { |p| p['name'] == n }
        write_catalog(rows)
        { ok: true, deleted: rows.length < before }
      end

      private

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../../..', __dir__)
        end
      end

      def load_catalog
        ensure_data_file!
        YAML.safe_load(File.read(@data_path), permitted_classes: [], aliases: false) || []
      rescue Psych::SyntaxError => e
        raise "invalid_yaml: #{e.message}"
      end

      def write_catalog(rows)
        File.write(@data_path, YAML.dump(rows))
      end

      def ensure_data_file!
        dir = File.dirname(@data_path)
        Dir.mkdir(dir) unless Dir.exist?(dir)
        return if File.exist?(@data_path)

        File.write(@data_path, YAML.dump([]))
      end

      def safe_yaml_load(text)
        YAML.safe_load(text.to_s, permitted_classes: [], aliases: false)
      rescue Psych::SyntaxError => e
        raise "invalid_yaml: #{e.message}"
      end

      def validate_entry!(p)
        %w[name version summary prompt_md].each do |req|
          raise "invalid_data: missing #{req}" unless p.key?(req) && !p[req].to_s.strip.empty?
        end
        v = coerce_version(p['version'])
        raise 'invalid_data: version must be integer >= 1' unless v.is_a?(Integer) && v >= 1

        p['version'] = v
      end

      def coerce_version(v)
        return nil if v.nil?
        return v if v.is_a?(Integer)
        if v.is_a?(String) && (m = v.match(/(\d+)/))
          return m[1].to_i
        end

        nil
      end

      def normalize_name(name)
        name.to_s.strip
      end
    end
  end
end
