# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require_relative '../../../../lib/savant/engines/context/fs/repo_indexer'
require_relative '../../../support/fakes/fake_db'

RSpec.describe Savant::Context::FS::RepoIndexer do
  let(:tmpdir) { Dir.mktmpdir }
  let(:cache_path) { File.join(tmpdir, 'cache', 'indexer.json') }
  let(:settings_path) { File.join(tmpdir, 'settings.json') }
  let(:db) { Support::FakeDB.new }

  before do
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(settings_path, JSON.pretty_generate(base_config))
  end

  after do
    FileUtils.remove_entry(tmpdir)
  end

  def base_config
    {
      'indexer' => {
        'maxFileSizeKB' => 0,
        'languages' => [],
        'chunk' => { 'mdMaxChars' => 1000, 'codeMaxLines' => 100, 'overlapLines' => 1 },
        'repos' => [
          { 'name' => 'dummy', 'path' => '/tmp' }
        ],
        'cachePath' => cache_path
      },
      'mcp' => { 'context' => {}, 'jira' => {} },
      'database' => { 'host' => 'h', 'port' => 1, 'db' => 'd', 'user' => 'u', 'password' => 'p' }
    }
  end

  def write_cache(data)
    File.write(cache_path, JSON.pretty_generate(data))
  end

  describe '#delete' do
    it 'removes the cache file when deleting all repos' do
      write_cache('foo::bar' => { 'size' => 1 })
      indexer = described_class.new(db: db, settings_path: settings_path)

      indexer.delete(repo: 'all')

      expect(File.exist?(cache_path)).to be(false)
      expect(db).to be_deleted_all
    end

    it 'removes only matching repo entries when deleting a specific repo' do
      write_cache('foo::bar' => { 'size' => 1 }, 'other::baz' => { 'size' => 2 })
      indexer = described_class.new(db: db, settings_path: settings_path)

      indexer.delete(repo: 'foo')

      data = JSON.parse(File.read(cache_path))
      expect(data.keys).to contain_exactly('other::baz')
      expect(db.deleted_repos).to include('foo')
    end
  end
end
