#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: List repository files respecting ignores and git excludes.
#
# Discovers files using either `git ls-files` (preferred) or directory walk
# fallback. Merges `.gitignore` and `.git/info/exclude` with optional extra
# ignore patterns. Tracks which method was used for transparency.

require 'find'
require 'open3'

module Savant
  module Indexer
    # Discovers repository files respecting git and custom ignores.
    #
    # Purpose: Provide a fast, consistent file list using `git ls-files` when
    # possible, falling back to a directory walk with glob-based ignores.
    class RepositoryScanner
      attr_reader :last_used

      def initialize(root, extra_ignores: [], scan_mode: :auto)
        @root = root
        raw_patterns = DEFAULT_IGNORE_GLOBS + Array(extra_ignores) + load_gitignore_patterns
        @ignore_patterns = normalize_globs(raw_patterns)
        @prune_names = derive_prune_dir_names(raw_patterns)
        @scan_mode = scan_mode
        @last_used = nil
      end

      def files
        return [] unless Dir.exist?(@root)

        if use_git?
          list = git_ls_files
          unless list.nil?
            @last_used = :git
            return list
          end
          # Fallback to walk on failure
        end
        @last_used = :walk
        out = []
        begin
          Find.find(@root) do |path|
            rel = path.sub(%r{^#{Regexp.escape(@root)}/?}, '')
            if File.directory?(path)
              # Skip .git and dot-directories or configured prunable dirs early
              next unless dot_dir?(rel) || prune_dir?(rel)

              Find.prune

            else
              next if rel.empty?
              next if ignored?(rel)

              out << [path, rel]
            end
          end
        rescue Errno::ENOENT
          return []
        end
        out
      end

      private

      # Default file-level ignore globs for compiled/binary artifacts and heavy outputs
      DEFAULT_IGNORE_GLOBS = %w[
        *.class *.jar *.war *.ear
        *.o *.a *.so *.dll *.dylib *.exe *.bin *.obj *.lib
        *.pyc *.pyo *.pyd
        *.wasm
        *.min.js *.bundle.js *.js.map *.css.map
        *.zip *.7z *.tar *.gz *.tgz *.bz2 *.xz
        *.pdf *.png *.jpg *.jpeg *.gif *.bmp *.ico *.webp
        *.psd *.ai *.sketch *.fig
        *.sqlite *.sqlite3 *.db *.db3
      ].freeze

      def dot_dir?(rel)
        rel == '.git' || rel.start_with?('.git/') || rel.split('/').any? { |part| part.start_with?('.') }
      end

      def prune_dir?(rel)
        # If any path segment is in prune_names, prune
        rel.split('/').any? { |seg| @prune_names.include?(seg) }
      end

      def ignored?(rel)
        @ignore_patterns.any? do |g|
          File.fnmatch?(g, rel, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
        end
      end

      def use_git?
        return false if @scan_mode == :walk
        return false unless Dir.exist?(File.join(@root, '.git'))

        true
      end

      def git_ls_files
        # Enumerate tracked and untracked (non-ignored) files
        cmd = [
          'git', '-C', @root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'
        ]
        stdout, status = Open3.capture2(*cmd)
        return nil unless status.success?

        rels = stdout.split("\x00").reject(&:empty?)
        # Drop anything under dot-directories (e.g., .git, .vscode, .idea, .cline, etc.)
        rels = rels.reject { |rel| rel.split('/').any? { |seg| seg.start_with?('.') } }
        # Drop files in known heavy/compiled output directories
        unless @prune_names.empty?
          rels = rels.reject { |rel| rel.split('/').any? { |seg| @prune_names.include?(seg) } }
        end
        # Apply extra ignore globs if provided
        rels = rels.reject { |rel| ignored?(rel) } unless @ignore_patterns.empty?
        rels.map { |rel| [File.join(@root, rel), rel] }
      rescue Errno::ENOENT
        # git not installed
        nil
      end

      def normalize_globs(patterns)
        patterns.map do |pat|
          p = pat.strip
          next if p.empty? || p.start_with?('#') || p.start_with?('!')

          p = "**/#{p}" unless p.include?('/')
          p = "#{p}**" if p.end_with?('/')
          p
        end.compact
      end

      def derive_prune_dir_names(patterns)
        names = []
        patterns.each do |pat|
          p = pat.strip
          next if p.empty? || p.start_with?('#') || p.start_with?('!')

          # Common directory ignore forms
          if p.end_with?('/**') || p.end_with?('/*') || p.end_with?('/')
            base = p.split('/').reject(&:empty?).last
            names << base.sub(/\*\*?$/, '') unless base.nil? || base.empty?
          elsif p !~ /[*\[\]?]/
            # Plain directory name
            names << p
          end
        end
        # Always prune canonical heavy dirs
        names.push('node_modules', 'vendor', 'dist', 'build', 'out', 'target', 'obj',
                   '__pycache__', '.next', '.nuxt', '.parcel-cache', '.gradle', '.mvn', '.git')
        names.uniq
      end

      def load_gitignore_patterns
        patterns = []
        [File.join(@root, '.gitignore'), File.join(@root, '.git', 'info', 'exclude')].each do |path|
          next unless File.file?(path)

          File.readlines(path, chomp: true).each do |line|
            line = line.strip
            next if line.empty? || line.start_with?('#')
            next if line.start_with?('!')

            patterns << line
          end
        end
        patterns
      end
    end
  end
end
