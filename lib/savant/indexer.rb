require 'json'
require 'digest'
require_relative 'config'
require_relative 'db'

module Savant
  class Indexer
    CACHE_PATH = '.cache/indexer.json'

    def initialize(settings_path)
      @cfg = Config.load(settings_path)
      @cache = load_cache
    end

    def run(repo_name = nil, verbose: true)
      targets = select_repos(repo_name)
      total = 0
      changed = 0
      skipped = 0
      db = Savant::DB.new
      targets.each do |repo|
        root = repo['path']
        ignores = Array(repo['ignore'])
        files = Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH)
                   .select { |p| File.file?(p) }
        files.each do |abs|
          rel = abs.sub(/^#{Regexp.escape(root)}\/?/, '')
          next if ignored?(rel, ignores)
          total += 1
          stat = File.stat(abs)
          key = cache_key(repo['name'], rel)
          meta = { 'size' => stat.size, 'mtime_ns' => (stat.mtime.nsec + stat.mtime.to_i * 1_000_000_000) }
          if unchanged?(key, meta)
            skipped += 1
            puts "UNCHANGED #{repo['name']}:#{rel}" if verbose
            next
          end
          # Compute hash and ensure blob exists (dedupe by content)
          hash = Digest::SHA256.file(abs).hexdigest
          Savant::DB.new # ensure class loaded
          blob_id = db.find_or_create_blob(hash, stat.size)
          @cache[key] = meta
          changed += 1
        end
      end
      save_cache
      puts "scanned=#{total} changed=#{changed} skipped=#{skipped}" if verbose
      { total: total, changed: changed, skipped: skipped }
    end

    private

    def select_repos(name)
      if name
        @cfg['repos'].select { |r| r['name'] == name }
      else
        @cfg['repos']
      end
    end

    def ignored?(rel, patterns)
      patterns.any? { |g| File.fnmatch?(g, rel, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB) }
    end

    def cache_key(repo, rel)
      "#{repo}::#{rel}"
    end

    def load_cache
      if File.exist?(CACHE_PATH)
        JSON.parse(File.read(CACHE_PATH))
      else
        {}
      end
    end

    def save_cache
      dir = File.dirname(CACHE_PATH)
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write(CACHE_PATH, JSON.pretty_generate(@cache))
    end
  end
end
