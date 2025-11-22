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
        totals = { total: 0, changed: 0, skipped: 0, errors: 0 }

        select_repos(repo_name).each do |repo|
          root = repo.fetch('path')
          ignores = Array(repo['ignore'])
          mode = @config.scan_mode_for(repo)
          scanner = RepositoryScanner.new(root, extra_ignores: ignores, scan_mode: mode)
          files = scanner.files
          repo_id = @store.ensure_repo(repo.fetch('name'), root)

          counts = process_repo(repo: repo, repo_id: repo_id, scanner: scanner, files: files, verbose: verbose)
          totals[:total] += files.length
          totals[:changed] += counts[:indexed]
          totals[:skipped] += counts[:skipped]
          totals[:errors] += counts[:errors]
          totals[:memory_bank] = (totals[:memory_bank] || 0) + (counts[:memory_bank] || 0)
          totals[:code_files] = (totals[:code_files] || 0) + (counts[:code_files] || 0)
          totals[:doc_files] = (totals[:doc_files] || 0) + (counts[:doc_files] || 0)
        end

        @cache.save!
        if verbose
          @log.info(
            "summary: scanned=#{totals[:total]} changed=#{totals[:changed]} " \
            "skipped=#{totals[:skipped]} errors=#{totals[:errors]}"
          )
          @log.info("memory_bank: #{totals[:memory_bank] || 0}")
          @log.info("doc_files: #{totals[:doc_files] || 0}")
          @log.info("code_files: #{totals[:code_files] || 0}")
        end
        totals
      end

      private

      def process_repo(repo:, repo_id:, scanner:, files:, verbose:)
        using = scanner.last_used == :git ? 'gitls' : 'ls'
        @log.repo_header(name: repo['name'], total: files.length, strategy: using)
        progress = verbose ? @log.progress_bar(title: 'indexing', total: files.length) : nil
        kept = []
        kind_counts = Hash.new(0)
        repo_indexed = 0
        repo_skipped = 0
        repo_errors = 0

        @store.with_transaction do
          files.each do |abs, rel|
            kept << rel
            begin
              stat = File.stat(abs)
              if too_large?(stat.size)
                repo_skipped += 1
                log_skip(rel, "too_large size=#{stat.size}B max=#{@config.max_bytes}B", verbose)
                progress&.increment
                next
              end

              key = cache_key(repo['name'], rel)
              meta = { 'size' => stat.size, 'mtime_ns' => to_ns(stat.mtime) }
              if unchanged?(key, meta)
                repo_skipped += 1
                log_skip(rel, 'unchanged', verbose)
                progress&.increment
                next
              end

              lang = Language.from_rel_path(rel)
              allowed = @config.languages
              # Always allow memory_bank markdown and doc-like files regardless of language allowlist;
              # otherwise enforce allowlist
              if !allowed.empty? && !allowed.include?(lang) && lang != 'memory_bank' && !doc_like?(rel, lang)
                repo_skipped += 1
                log_skip(rel, "unsupported_lang lang=#{lang}", verbose)
                progress&.increment
                next
              end

              if binary_file?(abs)
                repo_skipped += 1
                log_skip(rel, 'binary', verbose)
                progress&.increment
                next
              end

              hash = Digest::SHA256.file(abs).hexdigest
              blob_id = @store.ensure_blob(hash, stat.size)
              chunks = build_chunks(abs, lang).each_with_index.map { |chunk, idx| [idx, lang, chunk] }
              @store.write_chunks(blob_id, chunks)
              file_id = @store.upsert_file(repo_id, repo.fetch('name'), rel, stat.size, meta['mtime_ns'])
              @store.map_file(file_id, blob_id)

              @cache[key] = meta
              kind_counts[lang] += 1
              repo_indexed += 1
              progress&.increment
            rescue StandardError => e
              repo_skipped += 1
              repo_errors += 1
              @log.debug("error: repo=#{repo['name']} item=#{rel} class=#{e.class} msg=#{e.message.inspect}") if verbose
              progress&.increment
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
          mb = kind_counts['memory_bank'] || 0
          # Doc-only (exclude memory_bank which is tracked separately)
          doc_only_langs = (DOC_TEXT_EXTS + %w[md mdx markdown]).uniq
          doc_files = kind_counts.sum { |k, v| doc_only_langs.include?(k) ? v : 0 }
          # Code files exclude doc-only and memory_bank
          non_code = (doc_only_langs + %w[memory_bank]).uniq
          code_files = kind_counts.sum { |k, v| non_code.include?(k) ? 0 : v }
          @log.info("memory_bank: #{mb}")
          @log.info("doc_files: #{doc_files}")
          doc_breakdown = kind_counts.select { |k, _| doc_only_langs.include?(k) }
          code_breakdown = kind_counts.reject { |k, _| non_code.include?(k) }
          @log.info("doc_files_breakdown: #{doc_breakdown.map { |k, v| "#{k}=#{v}" }.join(' ')}") unless doc_breakdown.empty?
          @log.info("code_files_breakdown: #{code_breakdown.map { |k, v| "#{k}=#{v}" }.join(' ')}") unless code_breakdown.empty?
          @log.info("code_files: #{code_files}")
        end
        progress&.finish
        @log.repo_footer(indexed: repo_indexed, skipped: repo_skipped, errors: repo_errors)

        # include derived counts for aggregation in summary
        doc_only_langs = (DOC_TEXT_EXTS + %w[md mdx markdown]).uniq
        non_code = (doc_only_langs + %w[memory_bank]).uniq
        doc_files = kind_counts.sum { |k, v| doc_only_langs.include?(k) ? v : 0 }
        code_files = kind_counts.sum { |k, v| non_code.include?(k) ? 0 : v }
        { indexed: repo_indexed, skipped: repo_skipped, errors: repo_errors,
          memory_bank: kind_counts['memory_bank'] || 0, doc_files: doc_files, code_files: code_files }
      end

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
        time.nsec + (time.to_i * 1_000_000_000)
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
        when 'md', 'mdx', 'markdown', 'memory_bank'
          Chunker::MarkdownChunker.new.chunk(path, c)
        when 'txt', 'rst', 'adoc', 'asciidoc', 'org', 'rdoc'
          Chunker::PlaintextChunker.new.chunk(path, c)
        else
          Chunker::CodeChunker.new.chunk(path, c)
        end
      end

      def log_skip(rel, reason, verbose)
        @log.debug("skip: item=#{rel} reason=#{reason}") if verbose
      end

      DOC_TEXT_EXTS = %w[txt rst adoc asciidoc org rdoc].freeze
      DOC_BASE_NAMES = %w[readme license copying changelog contributing code_of_conduct security notice].freeze

      def doc_like?(rel, lang)
        base = File.basename(rel).downcase
        stem = File.basename(rel, File.extname(rel)).downcase
        return true if DOC_TEXT_EXTS.include?(lang)
        return true if DOC_BASE_NAMES.include?(stem)
        false
      end
    end
  end
end
