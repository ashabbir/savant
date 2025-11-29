# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require_relative '../lib/savant/engines/indexer/repository_scanner'

RSpec.describe Savant::Indexer::RepositoryScanner do
  it 'uses git ls-files when enabled and filters with config ignores' do
    # Make the scanner think the repo and .git exist
    allow(Dir).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).with('/repo').and_return(true)
    allow(Dir).to receive(:exist?).with('/repo/.git').and_return(true)

    # Stub git output to include ignored dirs; scanner should filter them
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2)
      .with('git', '-C', '/repo', 'ls-files', '-z', '--cached', '--others', '--exclude-standard')
      .and_return(["app/a.rb\x00dist/b.rb\x00tmp/c.rb\x00", status])

    scanner = described_class.new('/repo', extra_ignores: ['dist/**', 'tmp/**'], scan_mode: :git)
    files = scanner.files
    expect(files).to eq([['/repo/app/a.rb', 'app/a.rb']])
  end
end
# !/usr/bin/env ruby
# frozen_string_literal: true
