require 'json'
require 'time'
require_relative 'markdown'
require_relative 'summaries'
require_relative 'snippets'

module Savant
  module MemoryBank
    Resource = Struct.new(:uri, :mime_type, :path, :title, :size_bytes, :modified_at, :source, :summary, keyword_init: true)

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

    class Indexer
      def initialize(repo_name:, repo_root:, config: {})
        @repo_name = repo_name
        @repo_root = repo_root
        @cfg = config || {}
        @patterns = Array(@cfg.dig('memory_bank', 'patterns') || ['**/memory_bank/**/*.md'])
        @follow_symlinks = !!@cfg.dig('memory_bank', 'follow_symlinks')
        @max_bytes_index = (@cfg.dig('memory_bank', 'max_bytes_index') || 2_000_000).to_i
        @summary_max_length = (@cfg.dig('memory_bank', 'summary_max_length') || 300).to_i
        @summarize_enabled = @cfg.dig('memory_bank', 'summarize_enabled') != false
        @enabled = @cfg.dig('memory_bank', 'enabled') != false
      end

      def enabled?
        @enabled
      end

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
          summary = nil
          if @summarize_enabled && stat.size <= @max_bytes_index
            s = Summaries.summarize(text, max_length: @summary_max_length)
            summary = s
          end
          uri = "repo://#{@repo_name}/memory-bank/#{rel}"
          res = Resource.new(
            uri: uri,
            mime_type: 'text/markdown; charset=utf-8',
            path: rel,
            title: title,
            size_bytes: stat.size,
            modified_at: stat.mtime.utc.iso8601,
            source: 'memory_bank',
            summary: summary
          )
          index.add(res)
        end
        index
      end

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
          scored << [hits, { path: res.path, title: res.title, score: hits, summary: res.summary, snippets: snippets, metadata: { modified_at: res.modified_at, size_bytes: res.size_bytes, source: res.source } }]
        end
        scored.sort_by! { |(s, _)| -s }
        results = scored.map { |(_, r)| r }[0, max_results]
        { results: results, total: scored.length }
      end

      private
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
