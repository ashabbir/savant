#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative '../../framework/db'

module Savant
  module Personas
    # Ops for Personas engine: DB-backed CRUD for persona catalog.
    class Ops
      def initialize(db: nil)
        @db = db || Savant::Framework::DB.new
      end

      # List personas with optional filter on name|tags|summary
      # @return [Hash] { personas: [{ name, version, summary, tags }] }
      def list(filter: nil)
        rows = @db.list_personas(filter: filter)
        personas = rows.map do |r|
          {
            name: r['name'],
            version: r['version'].to_i,
            summary: r['summary'],
            tags: parse_pg_array(r['tags'])
          }
        end
        { personas: personas }
      end

      # Get a persona by name
      # @return [Hash] or raises 'not_found'
      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?

        row = @db.get_persona_by_name(key)
        raise 'not_found' unless row

        {
          name: row['name'],
          version: row['version'].to_i,
          summary: row['summary'],
          tags: parse_pg_array(row['tags']),
          prompt_md: row['prompt_md'],
          notes: row['notes']
        }
      end

      # Read a single persona as YAML text
      def read_persona_yaml(name:)
        data = get(name: name)
        { persona_yaml: YAML.dump(stringify_keys(data)) }
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

        entry_name = (entry['name'] || entry[:name]).to_s.strip
        entry_name = n if entry_name.empty?
        raise 'name_mismatch' unless entry_name == n

        existing = @db.get_persona_by_name(n)
        raise 'not_found' unless existing

        prev_ver = existing['version'].to_i
        new_ver = prev_ver + 1

        @db.update_persona(
          name: n,
          version: new_ver,
          summary: entry['summary'] || entry[:summary],
          prompt_md: entry['prompt_md'] || entry[:prompt_md],
          tags: entry['tags'] || entry[:tags],
          notes: entry['notes'] || entry[:notes]
        )
        { ok: true, name: n }
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end

      # Read full catalog as YAML
      def catalog_read
        rows = @db.list_personas
        catalog = rows.map do |r|
          {
            'name' => r['name'],
            'version' => r['version'].to_i,
            'summary' => r['summary'],
            'tags' => parse_pg_array(r['tags']),
            'prompt_md' => r['prompt_md'],
            'notes' => r['notes']
          }.compact
        end
        { catalog_yaml: YAML.dump(catalog) }
      end

      # Overwrite full catalog (replaces all personas)
      def catalog_write(yaml:)
        text = yaml.to_s
        rows = parse_and_validate_catalog(text)

        # Delete all existing, then insert new
        existing = @db.list_personas
        existing.each { |r| @db.delete_persona(r['name']) }

        rows.each do |entry|
          @db.create_persona(
            entry['name'],
            nil,
            version: entry['version'] || 1,
            summary: entry['summary'],
            prompt_md: entry['prompt_md'],
            tags: entry['tags'],
            notes: entry['notes']
          )
        end
        { ok: true, count: rows.size }
      end

      # Create persona
      def create(name:, summary:, prompt_md:, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        existing = @db.get_persona_by_name(n)
        raise 'already_exists' if existing

        @db.create_persona(
          n,
          nil,
          version: 1,
          summary: summary.to_s.strip,
          prompt_md: prompt_md.to_s,
          tags: Array(tags).map(&:to_s).reject(&:empty?),
          notes: notes
        )
        { ok: true, name: n }
      end

      # Update persona (partial allowed)
      def update(name:, **fields)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        existing = @db.get_persona_by_name(n)
        raise 'not_found' unless existing

        prev_ver = existing['version'].to_i
        new_ver = prev_ver + 1

        update_fields = { version: new_ver }
        update_fields[:summary] = fields[:summary].to_s if fields.key?(:summary) && !fields[:summary].nil?
        update_fields[:prompt_md] = fields[:prompt_md].to_s if fields.key?(:prompt_md) && !fields[:prompt_md].nil?
        if fields.key?(:tags)
          update_fields[:tags] = Array(fields[:tags]).map(&:to_s).reject(&:empty?)
        end
        if fields.key?(:notes)
          update_fields[:notes] = fields[:notes].nil? ? nil : fields[:notes].to_s
        end

        @db.update_persona(name: n, **update_fields)
        { ok: true, name: n }
      end

      # Delete persona
      def delete(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        deleted = @db.delete_persona(n)
        { ok: true, deleted: deleted }
      end

      private

      def normalize_name(name)
        name.to_s.strip
      end

      def parse_pg_array(val)
        return [] if val.nil?
        return val if val.is_a?(Array)

        # PG returns text[] as "{a,b,c}" string
        if val.is_a?(String) && val.start_with?('{') && val.end_with?('}')
          return val[1..-2].split(',').map(&:strip).reject(&:empty?)
        end
        []
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s)
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
