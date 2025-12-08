#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative '../../framework/db'

module Savant
  module Rules
    # Ops for Rules engine: DB-backed CRUD for ruleset catalog.
    class Ops
      def initialize(db: nil)
        @db = db || Savant::Framework::DB.new
      end

      # List rulesets with optional filter on name|tags|summary
      # @return [Hash] { rules: [{ id, name, version, summary, tags }] }
      def list(filter: nil)
        rows = @db.list_rulesets(filter: filter)
        rules = rows.map do |r|
          {
            id: generate_id(r['name']),
            name: r['name'],
            version: r['version'].to_i,
            summary: r['summary'],
            tags: parse_pg_array(r['tags'])
          }
        end
        { rules: rules }
      end

      # Get a ruleset by name
      # @return [Hash] or raises 'not_found'
      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?

        row = @db.get_ruleset_by_name(key)
        raise 'not_found' unless row

        {
          id: generate_id(row['name']),
          name: row['name'],
          version: row['version'].to_i,
          summary: row['summary'],
          tags: parse_pg_array(row['tags']),
          rules_md: row['rules_md'],
          notes: row['notes']
        }
      end

      # Read a single ruleset as YAML text
      # @return [Hash] { rule_yaml: String }
      def read_rule_yaml(name:)
        data = get(name: name)
        { rule_yaml: YAML.dump(stringify_keys(data)) }
      end

      # Overwrite a single ruleset from YAML
      # @return [Hash] { ok: true, name: String }
      def write_rule_yaml(name:, yaml:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        data = YAML.safe_load(yaml.to_s)
        entry = case data
                when Hash then data
                when Array then data.first || {}
                else {}
                end
        raise 'invalid_input: yaml must define a ruleset' if entry.empty?

        entry_name = (entry['name'] || entry[:name]).to_s.strip
        entry_name = n if entry_name.empty?
        raise 'name_mismatch' unless entry_name == n

        existing = @db.get_ruleset_by_name(n)
        raise 'not_found' unless existing

        prev_ver = existing['version'].to_i
        new_ver = prev_ver + 1

        @db.update_ruleset(
          name: n,
          version: new_ver,
          summary: entry['summary'] || entry[:summary],
          rules_md: entry['rules_md'] || entry[:rules_md],
          tags: entry['tags'] || entry[:tags],
          notes: entry['notes'] || entry[:notes]
        )
        { ok: true, name: n }
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end

      # Read the raw catalog YAML
      # @return [Hash] { catalog_yaml: String }
      def catalog_read
        rows = @db.list_rulesets
        catalog = rows.map do |r|
          {
            'id' => generate_id(r['name']),
            'name' => r['name'],
            'version' => r['version'].to_i,
            'summary' => r['summary'],
            'tags' => parse_pg_array(r['tags']),
            'rules_md' => r['rules_md'],
            'notes' => r['notes']
          }.compact
        end
        { catalog_yaml: YAML.dump(catalog) }
      end

      # Overwrite the entire catalog from YAML
      # @param yaml [String]
      # @return [Hash] { ok: true, count: Integer }
      def catalog_write(yaml:)
        text = yaml.to_s
        rows = parse_and_validate_catalog(text)

        # Delete all existing, then insert new
        existing = @db.list_rulesets
        existing.each { |r| @db.delete_ruleset(r['name']) }

        rows.each do |entry|
          @db.create_ruleset(
            entry['name'],
            nil,
            version: entry['version'] || 1,
            summary: entry['summary'],
            rules_md: entry['rules_md'],
            tags: entry['tags'],
            notes: entry['notes']
          )
        end
        { ok: true, count: rows.size }
      end

      # Create a single ruleset entry
      # @return [Hash] { ok: true, name: String }
      def create(name:, summary:, rules_md:, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        new_id = generate_id(n)
        existing = @db.get_ruleset_by_name(n)
        raise friendly_conflict_error(new_id, n) if existing

        @db.create_ruleset(
          n,
          nil,
          version: 1,
          summary: summary.to_s.strip,
          rules_md: rules_md.to_s,
          tags: Array(tags).map(&:to_s).reject(&:empty?),
          notes: notes
        )
        { ok: true, name: n }
      end

      # Update an existing ruleset entry (partial update allowed)
      # @param fields [Hash] optional keys: summary, rules_md, tags, notes
      # @return [Hash] { ok: true, name: String }
      def update(name:, **fields)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        existing = @db.get_ruleset_by_name(n)
        raise 'not_found' unless existing

        prev_ver = existing['version'].to_i
        new_ver = prev_ver + 1

        update_fields = { version: new_ver }
        update_fields[:summary] = fields[:summary].to_s if fields.key?(:summary)
        update_fields[:rules_md] = fields[:rules_md].to_s if fields.key?(:rules_md)
        if fields.key?(:tags)
          update_fields[:tags] = Array(fields[:tags]).map(&:to_s).reject(&:empty?)
        end
        if fields.key?(:notes)
          v = fields[:notes]
          update_fields[:notes] = v.nil? ? nil : v.to_s
        end

        @db.update_ruleset(name: n, **update_fields)
        { ok: true, name: n }
      end

      # Delete a ruleset entry by name
      # @return [Hash] { ok: true, deleted: Boolean }
      def delete(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        deleted = @db.delete_ruleset(n)
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

      # Generate a stable, snake_case id from a name
      def generate_id(name)
        s = name.to_s.downcase
        # best-effort ASCII
        begin
          s = s.encode('ASCII', invalid: :replace, undef: :replace, replace: '')
        rescue StandardError
          s = s.gsub(/[^\x00-\x7F]+/, '')
        end
        s = s.gsub(/[^a-z0-9]+/, '_')
        s = s.gsub(/_+/, '_')
        s = s.gsub(/^_+|_+$/, '')
        s.empty? ? 'unnamed' : s
      end

      def friendly_conflict_error(id, name)
        "conflict: A ruleset with id '#{id}' already exists (from name '#{name}'). Try a different name."
      end

      def parse_and_validate_catalog(yaml_text)
        data = YAML.safe_load(yaml_text)
        rows = data.is_a?(Array) ? data : []
        rows.each { |r| validate_entry!(r) }
        rows
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end

      def validate_entry!(r)
        %w[name version summary rules_md].each do |req|
          raise "invalid_data: missing #{req}" unless r.key?(req) && !r[req].to_s.strip.empty?
        end
        v = coerce_version(r['version'])
        raise 'invalid_data: version must be integer >= 1' unless v.is_a?(Integer) && v >= 1

        r['version'] = v
        # Ensure id presence (derive if missing)
        r['id'] = generate_id(r['name']) if !r['id'] || r['id'].to_s.strip.empty?
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
