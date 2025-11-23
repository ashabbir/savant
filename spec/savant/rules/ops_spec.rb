# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/savant/rules/ops'

RSpec.describe Savant::Rules::Ops do
  def write_yaml(dir, content)
    path = File.join(dir, 'lib', 'savant', 'rules')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'rules.yml'), content)
  end

  it 'lists and filters rules from YAML' do
    Dir.mktmpdir do |d|
      write_yaml(d, <<~YAML)
        - name: a
          title: A
          version: v1
          summary: alpha
          rules_md: "# A\n- one"
        - name: b
          title: B
          version: v1
          summary: beta
          tags: ["eng"]
          rules_md: "# B\n- two"
      YAML
      ops = described_class.new(root: d)
      all = ops.list
      expect(all[:rules].size).to eq(2)
      only = ops.list(filter: 'beta')
      expect(only[:rules].map { |r| r[:name] }).to eq(['b'])
      by_tag = ops.list(filter: 'eng')
      expect(by_tag[:rules].map { |r| r[:name] }).to eq(['b'])
    end
  end

  it 'gets a ruleset with markdown' do
    Dir.mktmpdir do |d|
      write_yaml(d, <<~YAML)
        - name: x
          title: X
          version: stable
          summary: s
          rules_md: "# X\n- rule"
      YAML
      ops = described_class.new(root: d)
      row = ops.get(name: 'x')
      expect(row[:name]).to eq('x')
      expect(row[:rules_md]).to include('# X')
    end
  end

  it 'raises on missing YAML' do
    Dir.mktmpdir do |d|
      ops = described_class.new(root: d)
      expect { ops.list }.to raise_error(/load_error/)
    end
  end
end

