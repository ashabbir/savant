# frozen_string_literal: true

require 'spec_helper'
require 'savant/core/config/loader'

RSpec.describe Savant::Core::Config::Loader do
  let(:tmp_path) { File.join('tmp', 'test_savant.yml') }

  before do
    Dir.mkdir('tmp') unless Dir.exist?('tmp')
  end

  after do
    File.delete(tmp_path) if File.exist?(tmp_path)
  end

  it 'loads YAML config when present' do
    File.write(tmp_path, "env: test\nfoo: bar\n")
    cfg = described_class.load(yaml_path: tmp_path)
    expect(cfg).to include('env' => 'test', 'foo' => 'bar')
  end

  it 'falls back to JSON settings when YAML not found' do
    cfg = described_class.load(yaml_path: File.join('tmp', 'missing.yml'))
    expect(cfg).to include('indexer', 'database')
  end
end

