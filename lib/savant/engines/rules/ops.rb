#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Savant
  module Rules
    # Ops loads and exposes rule catalog entries for engines and tools.
    class Ops
      def initialize(root: nil)
        @base = root || default_base_path
        @data_path = File.join(@base, 'lib', 'savant', 'engines', 'rules', 'rules.yml')
      end

      def list(filter: nil)
        rows = load_catalog.map do |r|
          # Ensure id exists or derive it on the fly for listing
          rid = r['id'] && !r['id'].to_s.strip.empty? ? r['id'].to_s : generate_id(r['name'].to_s)
          { id: rid, name: r['name'], version: r['version'], summary: r['summary'], tags: r['tags'] }
        end
        if filter && !filter.to_s.strip.empty?
          q = filter.to_s.downcase
          rows = rows.select { |h| [h[:name], h[:summary], Array(h[:tags]).join(' ')].any? { |v| v.to_s.downcase.include?(q) } }
        end
        { rules: rows }
      end

      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?

        row = load_catalog.find { |r| r['name'] == key }
        raise 'not_found' unless row

        {
          id: (row['id'] && !row['id'].to_s.strip.empty? ? row['id'] : generate_id(row['name'].to_s)),
          name: row['name'], version: row['version'], summary: row['summary'],
          tags: row['tags'], rules_md: row['rules_md'], notes: row['notes']
        }
      end

      # Read a single ruleset as YAML text
      # @return [Hash] { rule_yaml: String }
      def read_rule_yaml(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        row = rows.find { |r| r['name'] == n }
        raise 'not_found' unless row

        { rule_yaml: YAML.dump(row) }
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

        # Ensure required fields and name alignment
        entry['name'] = n if entry['name'].to_s.strip.empty?
        raise 'name_mismatch' unless entry['name'].to_s == n

        validate_entry!(entry)

        rows = load_catalog
        idx = rows.index { |r| r['name'] == n }
        raise 'not_found' unless idx

        # Bump version on YAML overwrite
        prev = rows[idx]
        prev_ver = coerce_version(prev['version'])
        entry['version'] = (prev_ver || 0) + 1
        rows[idx] = entry
        write_yaml_with_backup(@data_path, YAML.dump(rows))
        { ok: true, name: n }
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
      end

      # Read the raw catalog YAML
      # @return [Hash] { catalog_yaml: String }
      def catalog_read
        raise 'load_error: rules.yml not found' unless File.file?(@data_path)

        { catalog_yaml: read_text_utf8(@data_path) }
      end

      # Overwrite the entire catalog from YAML
      # @param yaml [String]
      # @return [Hash] { ok: true, count: Integer }
      def catalog_write(yaml:)
        text = yaml.to_s
        rows = parse_and_validate_catalog(text)
        write_yaml_with_backup(@data_path, YAML.dump(rows))
        { ok: true, count: rows.size }
      end

      # Create a single ruleset entry
      # @return [Hash] { ok: true, name: String }
      def create(name:, summary:, rules_md:, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        new_id = generate_id(n)
        rows = load_catalog
        # Disallow duplicate name or duplicate id (id is derived from name and immutable)
        raise friendly_conflict_error(new_id, n) if rows.any? { |r| r['name'] == n }
        raise friendly_conflict_error(new_id, n) if rows.any? { |r| (r['id'] && r['id'].to_s == new_id) || (!r['id'] && generate_id(r['name'].to_s) == new_id) }

        entry = {
          'id' => new_id,
          'name' => n,
          'version' => 1,
          'summary' => summary.to_s.strip,
          'rules_md' => rules_md.to_s
        }
        t = Array(tags).map(&:to_s).reject(&:empty?)
        entry['tags'] = t unless t.empty?
        entry['notes'] = notes.to_s unless notes.nil? || notes.to_s.strip.empty?
        validate_entry!(entry)
        rows << entry
        write_yaml_with_backup(@data_path, YAML.dump(rows))
        { ok: true, name: n }
      end

      # Update an existing ruleset entry (partial update allowed)
      # @param fields [Hash] optional keys: title, version, summary, rules_md, tags, notes
      # @return [Hash] { ok: true, name: String }
      def update(name:, **fields)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        idx = rows.index { |r| r['name'] == n }
        raise 'not_found' unless idx

        cur = rows[idx].dup
        # Apply changes
        cur['summary'] = fields[:summary].to_s if fields.key?(:summary)
        cur['rules_md'] = fields[:rules_md].to_s if fields.key?(:rules_md)
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
        write_yaml_with_backup(@data_path, YAML.dump(rows))
        { ok: true, name: n }
      end

      # Delete a ruleset entry by name
      # @return [Hash] { ok: true, deleted: Boolean }
      def delete(name:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        rows = load_catalog
        before = rows.length
        rows = rows.reject { |r| r['name'] == n }
        deleted = rows.length < before
        write_yaml_with_backup(@data_path, YAML.dump(rows))
        { ok: true, deleted: deleted }
      end

      private

      def default_base_path
        savant = ENV['SAVANT_PATH'].to_s
        return savant unless savant.empty?

        File.expand_path('../../../..', __dir__)
      end

      def load_catalog
        raise 'load_error: rules.yml not found' unless File.file?(@data_path)

        data = YAML.safe_load(read_text_utf8(@data_path))
        rows = data.is_a?(Array) ? data : []
        rows.each { |r| validate_entry!(r) }
        rows
      rescue Psych::SyntaxError => e
        raise "load_error: yaml syntax - #{e.message}"
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
        # Ensure id presence and format (derive if missing during validation)
        r['id'] = generate_id(r['name'].to_s) if !r['id'] || r['id'].to_s.strip.empty?
      end

      def coerce_version(v)
        return nil if v.nil?
        return v if v.is_a?(Integer)

        # Extract first integer occurrence (e.g., "v1" -> 1, "1" -> 1)
        if v.is_a?(String) && (m = v.match(/(\d+)/))
          return m[1].to_i
        end

        nil
      end

      def normalize_name(name)
        name.to_s.strip
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
        raise 'invalid_input: name must produce a non-empty id' if s.empty?

        s
      end

      def friendly_conflict_error(id, name)
        "conflict: A ruleset with id '#{id}' already exists (from name '#{name}'). Try a different name, e.g., add a qualifier like 'v2' -> '#{id}_v2'."
      end

      # Read a text file as UTF-8, tolerating BOM and invalid bytes.
      def read_text_utf8(path)
        File.open(path, 'r:bom|utf-8', &:read)
      rescue ArgumentError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        data = File.binread(path)
        data.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      end

      def write_yaml_with_backup(path, yaml_text)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        if File.exist?(path)
          ts = Time.now.utc.strftime('%Y%m%d%H%M%S')
          FileUtils.cp(path, "#{path}.bak#{ts}")
        end
        tmp = "#{path}.tmp"
        File.open(tmp, 'w:UTF-8') { |f| f.write(yaml_text) }
        FileUtils.mv(tmp, path)
      end
    end
  end
end
