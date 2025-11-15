# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../../lib/savant/indexer'
require_relative '../../support/fakes/fake_db'
require_relative '../../support/fakes/fake_cache'

RSpec.describe Savant::Indexer::Runner do
  let(:raw_cfg) do
    {
      'indexer' => {
        'maxFileSizeKB' => 512,
        'languages' => %w[rb md],
        'chunk' => { 'mdMaxChars' => 1000, 'codeMaxLines' => 200, 'overlapLines' => 3 },
        'repos' => [
          { 'name' => 'r', 'path' => '/repo', 'ignore' => ['tmp/**'] }
        ]
      },
      'mcp' => { 'listenHost' => '0.0.0.0', 'listenPort' => 1 },
      'database' => { 'host' => 'h', 'port' => 1, 'db' => 'd', 'user' => 'u', 'password' => 'p' }
    }
  end
  let(:config) { Savant::Indexer::Config.new(raw_cfg) }
  let(:db) { Support::FakeDB.new }
  let(:logger) { instance_double(Savant::Logger, info: nil, debug: nil) }
  let(:cache) { Support::FakeCache.new }

  subject(:runner) { described_class.new(config: config, db: db, logger: logger, cache: cache) }

  before do
    allow(logger).to receive(:with_timing).and_yield if logger.respond_to?(:with_timing)
  end

  def stub_file_ops(map)
    allow(File).to receive(:stat) do |abs|
      rel = abs.split('/').last
      cfg = map.fetch(rel)
      double('Stat', size: cfg[:size], mtime: cfg[:mtime])
    end
    allow(File).to receive(:open) do |abs, *_args, &blk|
      rel = abs.split('/').last
      cfg = map.fetch(rel)
      StringIO.open(cfg[:head] || cfg[:data]) { |io| blk&.call(io) }
    end
    allow(File).to receive(:read) do |abs|
      rel = abs.split('/').last
      map.fetch(rel)[:data]
    end
    allow(Digest::SHA256).to receive(:file) do |_abs|
      double('Dig', hexdigest: 'h')
    end
  end

  it 'logs walk_strategy gitls when git-based enumeration is used' do
    scanner = instance_double(Savant::Indexer::RepositoryScanner)
    allow(Savant::Indexer::RepositoryScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:files).and_return([
                                                   ['/repo/a.rb', 'a.rb']
                                                 ])
    allow(scanner).to receive(:last_used).and_return(:git)

    expect(logger).to receive(:info).with(/walk_strategy: gitls/).at_least(:once)

    map = { 'a.rb' => { size: 10, mtime: Time.at(100), data: "puts 1\n" } }
    stub_file_ops(map)

    runner.run(repo_name: 'r', verbose: false)
  end

  it 'emits repo header and footer counts' do
    scanner = instance_double(Savant::Indexer::RepositoryScanner)
    allow(Savant::Indexer::RepositoryScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:files).and_return([
                                                   ['/repo/a.rb', 'a.rb']
                                                 ])
    allow(scanner).to receive(:last_used).and_return(:walk)

    map = { 'a.rb' => { size: 10, mtime: Time.at(50), data: "puts 1\n" } }
    stub_file_ops(map)

    runner.run(repo_name: 'r', verbose: false)

    expect(logger).to have_received(:info).with('name: r')
    expect(logger).to have_received(:info).with('total_files: 1')
    expect(logger).to have_received(:info).with('indexed: 1')
    expect(logger).to have_received(:info).with('skipped: 0')
  end
end
