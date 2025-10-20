#!/usr/bin/env ruby
#
# Purpose: Lightweight scanner and searcher for memory_bank markdown files.
#
# Context::MemoryBank::Indexer discovers markdown resources under a repository
# (or any filesystem root) following patterns like `**/memory_bank/**/*.md`,
# builds a transient in‑memory index of resource metadata, and provides a
# simple substring‑based search with snippet generation. This is designed for
# quick local lookup without touching Postgres.
#
# Notes:
# - Does not compute summaries; summarization belongs to the indexing layer
#   responsible for persisting to Postgres.
# - `repo_name` is used only to construct stable repo:// URIs for resources.
# - `config` may customize glob patterns and symlink behavior.
#
require 'json'
require 'time'
require_relative 'markdown'
require_relative 'snippets'

module Savant
  module Context
    module MemoryBank
      Resource = Struct.new(:uri, :mime_type, :path, :title, :size_bytes, :modified_at, :source, keyword_init: true)

      # In‑memory collection of discovered memory_bank resources.
      class Index
        attr_reader :resources
        def initialize
          @resources = []
          @by_uri = {}
        end

      def clear!
        @resources.clear
        @by_uri.clear
      end

      def add(res)
        @by_uri[res.uri] = res
        @resources << res
      end

      def find(uri)
        @by_uri[uri]
      end
    end

      # Scanner/Searcher for memory_bank markdown beneath a repository root.
      class Indexer
        def initialize(repo_name:, repo_root:, config: {})
          @repo_name = repo_name
          @repo_root = repo_root
          @cfg = config || {}
          @patterns = Array(@cfg.dig('memory_bank', 'patterns') || ['**/memory_bank/**/*.md'])
          @follow_symlinks = !!@cfg.dig('memory_bank', 'follow_symlinks')
          @enabled = @cfg.dig('memory_bank', 'enabled') != false
        end

        # Whether scanning is enabled (configurable via memory_bank.enabled).
        def enabled?
          @enabled
        end

        # Discover markdown files and build an Index of Resource entries.
        def scan
          index = Index.new
          return index unless enabled?
          files = discover_files
          files.each do |abs|
          rel = abs.sub(/^#{Regexp.escape(@repo_root)}\/?/, '')
          stat = File.stat(abs) rescue nil
          next unless stat
          begin
            raw = File.read(abs)
          rescue
            raw = ''
          end
          text = Markdown.markdown_to_text(raw)
          title = Markdown.extract_title(raw, rel)
          uri = "repo://#{@repo_name}/memory-bank/#{rel}"
          res = Resource.new(
            uri: uri,
            mime_type: 'text/markdown; charset=utf-8',
            path: rel,
            title: title,
            size_bytes: stat.size,
            modified_at: stat.mtime.utc.iso8601,
            source: 'memory_bank'
          )
          index.add(res)
        end
        index
      end

        # Perform a naive substring search across discovered markdown resources
        # and produce contextual snippets around matches.
        # Returns: { results: [ { path, title, score, snippets, metadata } ], total }
        def search(index, query, max_results: 20, snippet_window: 160, windows_per_doc: 2)
          q = query.to_s.strip
          return { results: [], total: 0 } if q.empty?
          scored = []
          index.resources.each do |res|
          begin
            raw = File.read(File.join(@repo_root, res.path))
          rescue
            next
          end
          text = Markdown.markdown_to_text(raw)
          lc = text.downcase
          hits = lc.scan(Regexp.new(Regexp.escape(q.downcase))).length
          next if hits == 0
          snippets = Snippets.make_snippets(text, q, window: snippet_window, max_windows: windows_per_doc)
          scored << [hits, { path: res.path, title: res.title, score: hits, snippets: snippets, metadata: { modified_at: res.modified_at, size_bytes: res.size_bytes, source: res.source } }]
        end
        scored.sort_by! { |(s, _)| -s }
        results = scored.map { |(_, r)| r }[0, max_results]
        { results: results, total: scored.length }
      end

      private
      # Find matching markdown files under the repo root according to patterns.
      def discover_files
        flags = File::FNM_DOTMATCH
        paths = []
        @patterns.each do |pat|
          base = File.join(@repo_root, pat)
          Dir.glob(base, flags).each do |f|
            next unless File.file?(f)
            next unless f.downcase.end_with?('.md')
            next if !@follow_symlinks && File.symlink?(f)
            paths << f
          end
        end
        paths.uniq
      end
    end
    end
  end
end
