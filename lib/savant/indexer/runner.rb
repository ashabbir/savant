#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Coordinate scanning, chunking, and persistence per repo.
#
# Runner orchestrates repository scanning, filtering (size/lang/binary),
# hashing/dedup of blobs, chunk creation, and DB writes. It uses Cache to skip
# unchanged files and BlobStore for persistence.

require 'digest'

module Savant
  module Indexer
    # Coordinates repository scanning, chunking, and DB persistence.
    #
    # Purpose: Orchestrate the indexing flow per repo using RepositoryScanner,
    # Chunkers, and BlobStore with caching and progress logging.
    class Runner
      def initialize(config:, db:, logger:, cache:)
        @config = config
        @store = BlobStore.new(db)
        @log = Instrumentation.new(logger)
        @cache = cache
      end

      # Run the indexer across all or one repo.
      # @param repo_name [String,nil] optional repo name to filter
      # @param verbose [Boolean] emit per-file progress
      # @return [Hash] summary counts { total:, changed:, skipped: }
      def run(repo_name: nil, verbose: true)
        targets = select_repos(repo_name)
        total = 0
        changed = 0
        skipped = 0

        targets.each do |repo|
          root = repo.fetch('path')
          ignores = Array(repo['ignore'])
          mode = @config.scan_mode_for(repo)
          scanner = RepositoryScanner.new(root, extra_ignores: ignores, scan_mode: mode)
          files = scanner.files
          repo_id = @store.ensure_repo(repo.fetch('name'), root)
          using = scanner.last_used == :git ? 'gitls' : 'ls'
          @log.info("start: repo=#{repo['name']} total=#{files.length} using=#{using}")
          kept = []
          processed = 0
          kind_counts = Hash.new(0)

          @store.with_transaction do
            files.each do |abs, rel|
              kept << rel
              total += 1
              begin
                stat = File.stat(abs)
                if too_large?(stat.size)
                  skipped += 1
                  if verbose
                    @log.debug("skip: item=#{rel} reason=too_large size=#{stat.size}B max=#{@config.max_bytes}B")
                  end
                  next
                end

                key = cache_key(repo['name'], rel)
                meta = { 'size' => stat.size, 'mtime_ns' => to_ns(stat.mtime) }
                if unchanged?(key, meta)
                  skipped += 1
                  @log.debug("skip: item=#{rel} reason=unchanged") if verbose
                  next
                end

                # Allowed language filter
                lang = Language.from_rel_path(rel)
                allowed = @config.languages
                if !allowed.empty? && !allowed.include?(lang)
                  skipped += 1
                  @log.debug("skip: item=#{rel} reason=unsupported_lang lang=#{lang}") if verbose
                  next
                end

                # Binary check
                if binary_file?(abs)
                  skipped += 1
                  @log.debug("skip: item=#{rel} reason=binary") if verbose
                  next
                end

                # Hash and persist
                hash = Digest::SHA256.file(abs).hexdigest
                blob_id = @store.ensure_blob(hash, stat.size)
                chunks = build_chunks(abs, lang).each_with_index.map { |chunk, idx| [idx, lang, chunk] }
                @store.write_chunks(blob_id, chunks)
                file_id = @store.upsert_file(repo_id, repo.fetch('name'), rel, stat.size, meta['mtime_ns'])
                @store.map_file(file_id, blob_id)

                @cache[key] = meta
                kind_counts[lang] += 1
                changed += 1
                processed += 1
                pct = files.length.positive? ? ((processed.to_f / files.length) * 100).round : 100
                if verbose
                  @log.info("progress: repo=#{repo['name']} item=#{rel} done=#{processed}/#{files.length} (~#{pct}%)")
                end
              rescue StandardError => e
                skipped += 1
                @log.info("skip: item=#{rel} reason=error class=#{e.class} msg=#{e.message.inspect}") if verbose
                next
              end
            end

            begin
              @store.cleanup_missing(repo_id, kept)
            rescue StandardError => e
              if verbose
                @log.info("skip: repo=#{repo['name']} reason=cleanup_error class=#{e.class} msg=#{e.message.inspect}")
              end
            end
          end

          if kind_counts.any?
            counts_line = kind_counts.map { |k, v| "#{k}=#{v}" }.join(' ')
            @log.info("counts: #{counts_line}")
          end
          @log.info("complete: repo=#{repo['name']} total=#{files.length}")
        end

        @cache.save!
        @log.info("summary: scanned=#{total} changed=#{changed} skipped=#{skipped}") if verbose
        { total: total, changed: changed, skipped: skipped }
      end

      private

      def select_repos(name)
        if name
          @config.repos.select { |r| r['name'] == name }
        else
          @config.repos
        end
      end

      def cache_key(repo, rel)
        "#{repo}::#{rel}"
      end

      def unchanged?(key, meta)
        prev = @cache[key]
        prev.is_a?(Hash) && prev['size'] == meta['size'] && prev['mtime_ns'] == meta['mtime_ns']
      end

      def to_ns(time)
        time.nsec + time.to_i * 1_000_000_000
      end

      def too_large?(size)
        @config.max_bytes.positive? && size > @config.max_bytes
      end

      def binary_file?(path)
        File.open(path, 'rb') do |f|
          head = f.read(4096) || ''
          return head.include?("\x00")
        end
      end

      def build_chunks(path, lang)
        c = @config.chunk
        case lang
        when 'md', 'mdx'
          Chunker::MarkdownChunker.new.chunk(path, c)
        when 'txt'
          Chunker::PlaintextChunker.new.chunk(path, c)
        else
          Chunker::CodeChunker.new.chunk(path, c)
        end
      end
    end
  end
end
