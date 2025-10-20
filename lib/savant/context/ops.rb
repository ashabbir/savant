require 'json'
require_relative '../logger'

module Savant
  module Context
    class Ops
      def initialize
        @log = Savant::Logger.new(component: 'context.ops')
      end

      def search(q:, repo:, limit:)
        require_relative 'fts'
        Savant::Context::FTS.new.search(q: q, repo: repo, limit: limit)
      end

      def search_memory(q:, repo:, limit:)
        root = (ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__)); settings_path = File.join(root, 'config', 'settings.json')
        cfg = JSON.parse(File.read(settings_path)) rescue {}
        repos = cfg.dig('indexer','repos') || []
        repo_name = repo || repos.dig(0, 'name')
        repo_cfg = repos.find { |r| r['name'] == repo_name } || repos.first
        raise 'no repos configured' unless repo_cfg
        require_relative '../memory_bank/indexer'
        mbi = Savant::MemoryBank::Indexer.new(repo_name: repo_cfg['name'], repo_root: repo_cfg['path'], config: cfg)
        idx = mbi.scan
        window = Integer(cfg.dig('search','snippet_window') || 160) rescue 160
        windows = Integer(cfg.dig('search','snippet_windows_per_doc') || 2) rescue 2
        mbi.search(idx, q, max_results: limit, snippet_window: window, windows_per_doc: windows)
      end

      def resources_list(repo: nil)
        root = (ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__)); settings_path = File.join(root, 'config', 'settings.json')
        cfg = JSON.parse(File.read(settings_path)) rescue {}
        repos = cfg.dig('indexer','repos') || []
        repo_name = repo || repos.dig(0, 'name')
        repo_cfg = repos.find { |r| r['name'] == repo_name } || repos.first
        raise 'no repos configured' unless repo_cfg
        require_relative '../memory_bank/indexer'
        mbi = Savant::MemoryBank::Indexer.new(repo_name: repo_cfg['name'], repo_root: repo_cfg['path'], config: cfg)
        idx = mbi.scan
        idx.resources.map do |r|
          { uri: r.uri, mimeType: r.mime_type, metadata: { path: r.path, title: r.title, size_bytes: r.size_bytes, modified_at: r.modified_at, source: r.source, summary: r.summary } }
        end
      end

      def resources_read(uri:)
        unless uri.start_with?('repo://') && uri.include?('/memory-bank/')
          raise 'unsupported uri'
        end
        repo_name = uri.sub(/^repo:\/\//,'').split('/').first
        root = (ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__)); settings_path = File.join(root, 'config', 'settings.json')
        cfg = JSON.parse(File.read(settings_path)) rescue {}
        repo = (cfg.dig('indexer','repos') || []).find { |r| r['name'] == repo_name }
        raise 'repo not found' unless repo
        rel = uri.split('/memory-bank/',2)[1]
        abs = File.join(repo['path'], rel)
        File.read(abs)
      end
    end
  end
end
