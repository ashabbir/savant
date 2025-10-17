require 'json'
require 'digest'
require_relative 'config'
require_relative 'db'
require_relative 'logger'

module Savant
  class Indexer
    CACHE_PATH = '.cache/indexer.json'

    def initialize(settings_path)
      @cfg = Config.load(settings_path)
      @cache = load_cache
    end

    def run(repo_name = nil, verbose: true)
      log = Savant::Logger.new(component: 'indexer')
      targets = select_repos(repo_name)
      total = 0
      changed = 0
      skipped = 0
      db = Savant::DB.new
      targets.each do |repo|
        root = repo['path']
        ignores = Array(repo['ignore'])
        # Merge patterns from .gitignore and .git/info/exclude
        ignores.concat(load_gitignore_patterns(root))
        files = Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH)
                   .select { |p| File.file?(p) }
        repo_id = db.find_or_create_repo(repo['name'], root)
        log.info("start: repo=#{repo['name']} total=#{files.length}")
        kept = []
        processed = 0
        kind_counts = Hash.new(0)
        files.each do |abs|
          rel = abs.sub(/^#{Regexp.escape(root)}\/?/, '')
          if ignored?(rel, ignores)
            log.debug("skip: item=#{rel} reason=ignored") if verbose
            next
          end
          kept << rel
          total += 1
          begin
            stat = File.stat(abs)
            # Skip files larger than configured max size (KB)
            max_bytes = (@cfg['indexer']['maxFileSizeKB'].to_i) * 1024
            if max_bytes > 0 && stat.size > max_bytes
              skipped += 1
              log.debug("skip: item=#{rel} reason=too_large size=#{stat.size}B max=#{max_bytes}B") if verbose
              next
            end
            key = cache_key(repo['name'], rel)
            meta = { 'size' => stat.size, 'mtime_ns' => (stat.mtime.nsec + stat.mtime.to_i * 1_000_000_000) }
            if unchanged?(key, meta)
              skipped += 1
              log.debug("skip: item=#{rel} reason=unchanged") if verbose
              next
            end
          # Compute hash and ensure blob exists (dedupe by content)
          hash = Digest::SHA256.file(abs).hexdigest
          Savant::DB.new # ensure class loaded
          blob_id = db.find_or_create_blob(hash, stat.size)
          # Chunk file content according to settings
          lang = lang_for(rel)
          # Skip files with extensions not in allowed language list (if provided)
          allowed = Array(@cfg.dig('indexer', 'languages')).map { |s| s.to_s.downcase }
          if !allowed.empty? && !allowed.include?(lang)
            skipped += 1
            log.debug("skip: item=#{rel} reason=unsupported_lang lang=#{lang}") if verbose
            next
          end
          # Quick binary detection — skip if head contains NUL byte
          File.open(abs, 'rb') do |f|
            head = f.read(4096) || ""
            if head.include?("\x00")
              skipped += 1
              log.debug("skip: item=#{rel} reason=binary") if verbose
              next
            end
          end
          log.debug("classify: item=#{rel} kind=#{lang}") if verbose
          kind_counts[lang] += 1
          chunks = build_chunks(abs, lang)
            db.replace_chunks(blob_id, chunks)
            file_id = db.upsert_file(repo_id, rel, stat.size, meta['mtime_ns'])
            db.map_file_to_blob(file_id, blob_id)
            @cache[key] = meta
            changed += 1
            processed += 1
            pct = files.length > 0 ? ((processed.to_f / files.length) * 100).round : 100
            log.info("progress: repo=#{repo['name']} item=#{rel} done=#{processed}/#{files.length} (~#{pct}%)") if verbose
          rescue => e
            skipped += 1
            log.info("skip: item=#{rel} reason=error class=#{e.class} msg=#{e.message.inspect}") if verbose
            next
          end
        end
        # Remove files no longer present
        begin
          db.delete_missing_files(repo_id, kept)
        rescue => e
          log.info("skip: repo=#{repo['name']} reason=cleanup_error class=#{e.class} msg=#{e.message.inspect}") if verbose
        end
        # Emit counts summary
        if kind_counts.any?
          counts_line = kind_counts.map { |k,v| "#{k}=#{v}" }.join(' ')
          log.info("counts: #{counts_line}")
        end
        log.info("complete: repo=#{repo['name']} total=#{files.length}")
      end
      save_cache
      log.info("summary: scanned=#{total} changed=#{changed} skipped=#{skipped}") if verbose
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
      # Always skip .git and any hidden (dot) files or directories
      return true if rel == '.git' || rel.start_with?('.git/')
      return true if rel.split('/').any? { |part| part.start_with?('.') }
      patterns.any? { |g|
        File.fnmatch?(g, rel, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
      }
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

    def load_gitignore_patterns(root)
      patterns = []
      [File.join(root, '.gitignore'), File.join(root, '.git', 'info', 'exclude')].each do |path|
        next unless File.file?(path)
        File.readlines(path, chomp: true).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')
          next if line.start_with?('!') # negation not supported in this simple matcher
          pat = line
          # Treat patterns without '/' as matching in any subdirectory
          pat = "**/#{pat}" unless pat.include?('/')
          # Ensure directories ending with '/' match all under them
          pat = "#{pat}**" if pat.end_with?('/')
          patterns << pat
        end
      end
      patterns
    end

    def lang_for(rel)
      ext = File.extname(rel).downcase.sub('.', '')
      ext.empty? ? 'txt' : ext
    end

    def build_chunks(path, lang)
      data = File.read(path)
      c = @cfg['indexer']['chunk']
      if %w[md mdx].include?(lang)
        max = c['mdMaxChars']
        slices = []
        i = 0
        while i < data.length
          j = [i + max, data.length].min
          slices << data[i...j]
          i = j
        end
      else
        max_lines = c['codeMaxLines']
        overlap = c['overlapLines']
        lines = data.lines
        slices = []
        i = 0
        while i < lines.length
          j = [i + max_lines, lines.length].min
          slices << lines[i...j].join
          break if j >= lines.length
          next_i = j - overlap
          # Ensure forward progress; if overlap would stall, advance to j
          i = next_i <= i ? j : next_i
        end
      end
      slices.each_with_index.map { |chunk, idx| [idx, lang, chunk] }
    end

    def unchanged?(key, meta)
      prev = @cache[key]
      return false unless prev.is_a?(Hash)
      prev['size'] == meta['size'] && prev['mtime_ns'] == meta['mtime_ns']
    end
  end
end
