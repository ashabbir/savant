#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

module Savant
  module Personas
    # Ops for Personas engine: loads YAML catalog and implements list/get.
    class Ops
      def initialize(root: nil)
        @base = root || default_base_path
        @data_path = File.join(@base, 'lib', 'savant', 'engines', 'personas', 'personas.yml')
      end

      # List personas with optional filter on name|tags|summary
      # @return [Hash] { personas: [{ name, version, summary, tags? }] }
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
          version: row['version'],
          summary: row['summary'],
          tags: row['tags'],
          prompt_md: row['prompt_md'],
          notes: row['notes']
        }
      end

      # Read a single persona as YAML text
      def read_persona_yaml(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        row = rows.find { |p| p['name'] == n }
        raise 'not_found' unless row

        { persona_yaml: YAML.dump(row) }
      end

      # Overwrite a single persona from YAML
      def write_persona_yaml(name:, yaml:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        data = YAML.safe_load(yaml.to_s)
        entry = case data
                when Hash then data
                when Array then data.first || {}
                else {}
                end
        raise 'invalid_input: yaml must define a persona' if entry.empty?

        # Ensure required fields and name alignment
        entry['name'] = n if entry['name'].to_s.strip.empty?
        raise 'name_mismatch' unless entry['name'].to_s == n

        validate_entry!(entry)

        rows = load_catalog
        idx = rows.index { |p| p['name'] == n }
        raise 'not_found' unless idx

        # Bump version on YAML overwrite
        prev = rows[idx]
        prev_ver = coerce_version(prev['version'])
        entry['version'] = (prev_ver || 0) + 1
        rows[idx] = entry
        write_yaml(@data_path, YAML.dump(rows))
        { ok: true, name: n }
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end

      # Read full catalog
      def catalog_read
        raise 'load_error: personas.yml not found' unless File.file?(@data_path)

        { catalog_yaml: File.read(@data_path) }
      end

      # Overwrite full catalog
      def catalog_write(yaml:)
        text = yaml.to_s
        rows = parse_and_validate_catalog(text)
        write_yaml(@data_path, YAML.dump(rows))
        { ok: true, count: rows.size }
      end

      # Create persona
      def create(name:, summary:, prompt_md:, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        raise 'already_exists' if rows.any? { |p| p['name'] == n }

        entry = {
          'name' => n,
          'version' => 1,
          'summary' => summary.to_s.strip,
          'prompt_md' => prompt_md.to_s
        }
        t = Array(tags).map(&:to_s).reject(&:empty?)
        entry['tags'] = t unless t.empty?
        entry['notes'] = notes.to_s unless notes.nil? || notes.to_s.strip.empty?
        validate_entry!(entry)
        rows << entry
        write_yaml(@data_path, YAML.dump(rows))
        { ok: true, name: n }
      end

      # Update persona (partial allowed)
      def update(name:, **fields)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        idx = rows.index { |p| p['name'] == n }
        raise 'not_found' unless idx

        cur = rows[idx].dup
        # Only update scalar fields when an explicit non-nil value is provided;
        # avoid clobbering existing values with empty strings from nil.to_s
        cur['summary'] = fields[:summary].to_s if fields.key?(:summary) && !fields[:summary].nil?
        cur['prompt_md'] = fields[:prompt_md].to_s if fields.key?(:prompt_md) && !fields[:prompt_md].nil?
        if fields.key?(:tags)
          tags = Array(fields[:tags]).map(&:to_s).reject(&:empty?)
          if tags.empty?
            cur.delete('tags')
          else
            cur['tags'] = tags
          end
        end
        if fields.key?(:notes)
          v = fields[:notes]
          if v.nil? || v.to_s.strip.empty?
            cur.delete('notes')
          else
            cur['notes'] = v.to_s
          end
        end
        # Bump version automatically (integer)
        begin
          prev_ver = coerce_version(cur['version'])
          cur['version'] = (prev_ver || 0) + 1
        rescue StandardError
          cur['version'] = 1
        end
        validate_entry!(cur)
        rows[idx] = cur
        write_yaml(@data_path, YAML.dump(rows))
        { ok: true, name: n }
      end

      # Delete persona
      def delete(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        before = rows.length
        rows = rows.reject { |p| p['name'] == n }
        deleted = rows.length < before
        write_yaml(@data_path, YAML.dump(rows))
        { ok: true, deleted: deleted }
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
        raise 'load_error: personas.yml not found' unless File.file?(@data_path)

        data = YAML.safe_load(File.read(@data_path))
        rows = data.is_a?(Array) ? data : []
        rows.each { |p| validate_entry!(p) }
        rows
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      rescue StandardError => e
        raise e
      end

      def parse_and_validate_catalog(yaml_text)
        data = YAML.safe_load(yaml_text)
        rows = data.is_a?(Array) ? data : []
        rows.each { |p| validate_entry!(p) }
        rows
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end

      def validate_entry!(p)
        %w[name version summary prompt_md].each do |req|
          raise "invalid_data: missing #{req}" unless p.key?(req) && !p[req].to_s.strip.empty?
        end
        v = coerce_version(p['version'])
        raise 'invalid_data: version must be integer >= 1' unless v.is_a?(Integer) && v >= 1

        p['version'] = v
      end

      def normalize_name(name)
        name.to_s.strip
      end

      def write_yaml(path, text)
        File.write(path, text)
      end

      def coerce_version(v)
        return nil if v.nil?
        return v if v.is_a?(Integer)

        if v.is_a?(String) && (m = v.match(/(\d+)/))
          return m[1].to_i
        end

        nil
      end
    end
  end
end
