require 'json'

module Savant
  class ConfigError < StandardError; end

  class Config
    def self.load(path)
      raise ConfigError, "SETTINGS_PATH not provided" if path.nil? || path.strip.empty?
      unless File.exist?(path)
        raise ConfigError, "missing settings.json at #{path}"
      end
      begin
        data = JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ConfigError, "invalid JSON: #{e.message}"
      end

      validate!(data)
      data
    end

    def self.validate!(cfg)
      # Validate new layout: indexer + repos + mcp + database at root
      req = {
        'indexer' => %w[maxFileSizeKB languages chunk repos],
        'mcp' => nil,
        'database' => %w[host port db user password]
      }

      req.each do |key, inner|
        raise ConfigError, "missing key: #{key}" unless cfg.key?(key)
        if inner
          inner.each do |sub|
            raise ConfigError, "missing key: #{key}.#{sub}" unless cfg[key].is_a?(Hash) && cfg[key].key?(sub)
          end
        end
      end

      unless cfg.dig('indexer','repos').is_a?(Array) && cfg['indexer']['repos'].any?
        raise ConfigError, "repos must be a non-empty array"
      end
      cfg['indexer']['repos'].each do |r|
        raise ConfigError, "repo missing name" unless r['name'].is_a?(String) && !r['name'].empty?
        raise ConfigError, "repo #{r['name']} missing path" unless r['path'].is_a?(String) && !r['path'].empty?
        if r['ignore'] && !r['ignore'].is_a?(Array)
          raise ConfigError, "repo #{r['name']} ignore must be array"
        end
      end
      true
    end
  end
end
