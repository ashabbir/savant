#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative '../../framework/db'

module Savant
  module Drivers
    # Ops for Drivers engine: DB-backed CRUD for driver prompt catalog.
    class Ops
      def initialize(db: nil)
        @db = db || Savant::Framework::DB.new
      end

      # List drivers with optional filter on name|tags|summary
      # @return [Hash] { drivers: [{ name, version, summary, tags }] }
      def list(filter: nil)
        rows = @db.list_drivers(filter: filter)
        drivers = rows.map do |r|
          {
            name: r['name'],
            version: r['version'].to_i,
            summary: r['summary'],
            tags: parse_pg_array(r['tags'])
          }
        end
        { drivers: drivers }
      end

      # Get a driver by name
      # @return [Hash] or raises 'not_found'
      def get(name:)
        key = name.to_s.strip
        raise 'invalid_input: name required' if key.empty?

        row = @db.get_driver_by_name(key)
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

      # Read a single driver as YAML text
      def read_driver_yaml(name:)
        data = get(name: name)
        { driver_yaml: YAML.dump(stringify_keys(data)) }
      end

      # Overwrite a single driver from YAML
      def write_driver_yaml(name:, yaml:)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        data = safe_yaml_load(yaml)
        validate_entry!(data)

        existing = @db.get_driver_by_name(n)
        raise 'not_found' unless existing

        prev_ver = existing['version'].to_i
        new_ver = prev_ver + 1

        @db.update_driver(
          name: n,
          version: new_ver,
          summary: data['summary'],
          prompt_md: data['prompt_md'],
          tags: data['tags'],
          notes: data['notes']
        )
        { ok: true, name: n }
      end

      # Read entire catalog as YAML
      def catalog_read
        rows = @db.list_drivers
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

      # Overwrite catalog with YAML array
      def catalog_write(yaml:)
        rows = safe_yaml_load(yaml)
        raise 'invalid_yaml: expected an array' unless rows.is_a?(Array)

        rows.each { |p| validate_entry!(p) }

        # Delete all existing, then insert new
        existing = @db.list_drivers
        existing.each { |r| @db.delete_driver(r['name']) }

        rows.each do |entry|
          @db.create_driver(
            name: entry['name'],
            version: entry['version'] || 1,
            summary: entry['summary'],
            prompt_md: entry['prompt_md'],
            tags: entry['tags'],
            notes: entry['notes']
          )
        end
        { ok: true, count: rows.length }
      end

      # CRUD
      def create(name:, summary:, prompt_md:, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        existing = @db.get_driver_by_name(n)
        raise 'conflict: name already exists' if existing

        @db.create_driver(
          name: n,
          version: 1,
          summary: summary.to_s,
          prompt_md: prompt_md.to_s,
          tags: Array(tags).map(&:to_s).reject(&:empty?),
          notes: notes
        )
        { ok: true, name: n }
      end

      def update(name:, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        n = normalize_name(name)
        raise 'invalid_input: name required' if n.empty?

        existing = @db.get_driver_by_name(n)
        raise 'not_found' unless existing

        prev_ver = existing['version'].to_i
        new_ver = prev_ver + 1

        update_fields = { version: new_ver }
        update_fields[:summary] = summary unless summary.nil?
        update_fields[:prompt_md] = prompt_md unless prompt_md.nil?
        update_fields[:tags] = Array(tags).map(&:to_s) unless tags.nil?
        update_fields[:notes] = notes unless notes.nil?

        @db.update_driver(name: n, **update_fields)
        { ok: true, name: n }
      end

      def delete(name:)
        n = normalize_name(name)
        deleted = @db.delete_driver(n)
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
    end
  end
end
