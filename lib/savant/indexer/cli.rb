#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: CLI helpers for indexer entrypoints.
#
# Provides thin wiring for bin/index and admin commands to call the indexer
# facade with appropriate arguments and output formatting.

module Savant
  module Indexer
    # Minimal CLI wrapper for indexer admin/index commands.
    #
    # Purpose: Parse argv and invoke the indexer façade with sensible output.
    class CLI
      def self.run(argv)
        cmd = argv[0]
        settings_path = 'config/settings.json'

        if cmd.nil?
          warn 'usage: index all | index <repo> | delete all | delete <repo>'
          exit 2
        end

        repo = if cmd == 'all'
                 nil
               else
                 (cmd.start_with?('delete') ? argv[1] : cmd)
               end
        started = Time.now
        if cmd == 'delete'
          db = Savant::DB.new
          if repo.nil? || repo == 'all'
            puts "DELETE START ts=#{started.utc.iso8601} mode=all"
            db.delete_all_data
            res = { total: 0, changed: 0, skipped: 0 }
          else
            puts "DELETE START ts=#{started.utc.iso8601} repo=#{repo}"
            n = db.delete_repo_by_name(repo)
            res = { total: 0, changed: n, skipped: 0 }
          end
          action = 'DELETE'
        else
          mode = repo ? "repo=#{repo}" : 'all'
          # Surface configured scanMode (ls|git-ls); actual per-repo usage is logged by Runner
          begin
            raw = Savant::Config.load(settings_path)
            icfg = Savant::Indexer::Config.new(raw)
            scan = if repo
                     target = icfg.repos.find { |r| r['name'] == repo } || {}
                     icfg.scan_mode_for(target)
                   else
                     icfg.scan_mode
                   end
            scan_str = (scan == :git ? 'git-ls' : 'ls')
          rescue StandardError
            scan_str = 'unknown'
          end
          puts "INDEX START ts=#{started.utc.iso8601} settings=#{settings_path} mode=#{mode} scanMode=#{scan_str}"
          idx = Savant::Indexer::Facade.new(settings_path)
          res = idx.run(repo, verbose: true)
          action = 'INDEX'
        end
        finished = Time.now
        dur = (finished - started).round(3)
        puts "#{action} DONE ts=#{finished.utc.iso8601} duration_s=#{dur} total=#{res[:total]} changed=#{res[:changed]} skipped=#{res[:skipped]}"
      rescue Savant::ConfigError => e
        warn "CONFIG ERROR: #{e.message}"
        exit 1
      rescue StandardError => e
        warn "INDEX ERROR: #{e.class}: #{e.message}"
        exit 1
      end
    end
  end
end
