#!/usr/bin/env ruby
# frozen_string_literal: true

require 'tmpdir'
require 'open3'

RSpec.describe 'Savant::Git::Engine' do
  def sh(cmd, dir)
    out, err, st = Open3.capture3(cmd, chdir: dir)
    raise "cmd failed: #{cmd} err=#{err}" unless st.success?

    out
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  it 'provides repo status, changed files, diff, hunks, and file context' do
    Dir.mktmpdir do |dir|
      sh('git init .', dir)
      sh('git config user.name test', dir)
      sh('git config user.email test@example.com', dir)
      write(File.join(dir, 'hello.txt'), "hello\n")
      sh('git add hello.txt', dir)
      sh('git commit -m init', dir)

      # Modify file in worktree
      write(File.join(dir, 'hello.txt'), "hello\nworld\n")

      # Load engine and call tools
      require_relative '../../../lib/savant/engines/git/engine'
      engine = Savant::Git::Engine.new

      st = engine.repo_status(path: dir)
      expect(st[:is_repo]).to eq(true)
      expect(st[:path]).to eq(dir)
      expect(st[:head]).not_to be_nil

      changed = engine.changed_files
      expect(changed.any? { |r| r[:path] == 'hello.txt' }).to eq(true)

      diffs = engine.diff
      entry = diffs.find { |e| e[:path] == 'hello.txt' }
      expect(entry).not_to be_nil
      expect(entry[:hunks].size).to be >= 1

      hs = engine.hunks
      h = hs.find { |e| e[:path] == 'hello.txt' }[:hunks].first
      expect(h[:added_lines]).to include(2)

      # read_file and file_context
      head_text = engine.read_file(path: 'hello.txt', at: 'HEAD')
      expect(head_text).to include('hello')
      expect(head_text).not_to include('world')

      ctx = engine.file_context(path: 'hello.txt', line: 2, before: 1, after: 0)
      expect(ctx[:line]).to eq('world')
    end
  end
end

