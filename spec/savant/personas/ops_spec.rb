# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/savant/personas/ops'

RSpec.describe Savant::Personas::Ops do
  def write_yaml(dir, content)
    path = File.join(dir, 'lib', 'savant', 'personas')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'personas.yml'), content)
  end

  it 'lists and filters personas from YAML' do
    Dir.mktmpdir do |d|
      write_yaml(d, <<~YAML)
        - name: a
          title: A
          version: v1
          summary: alpha persona
          prompt_md: |
            hi A
        - name: b
          title: B
          version: v1
          summary: beta persona
          tags: ["eng"]
          prompt_md: |
            hi B
      YAML
      ops = described_class.new(root: d)
      all = ops.list
      expect(all[:personas].size).to eq(2)
      only = ops.list(filter: 'beta')
      expect(only[:personas].map { |r| r[:name] }).to eq(['b'])
      by_tag = ops.list(filter: 'eng')
      expect(by_tag[:personas].map { |r| r[:name] }).to eq(['b'])
    end
  end

  it 'gets a persona with full prompt' do
    Dir.mktmpdir do |d|
      write_yaml(d, <<~YAML)
        - name: x
          title: X
          version: stable
          summary: summary
          prompt_md: |
            test prompt
      YAML
      ops = described_class.new(root: d)
      row = ops.get(name: 'x')
      expect(row[:name]).to eq('x')
      expect(row[:prompt_md]).to include('test prompt')
    end
  end

  it 'raises on missing YAML' do
    Dir.mktmpdir do |d|
      ops = described_class.new(root: d)
      expect { ops.list }.to raise_error(/load_error/)
    end
  end
end

