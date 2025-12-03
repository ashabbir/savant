# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'yaml'
require_relative '../spec_helper'
require_relative '../../lib/savant/engines/workflow/loader'

RSpec.describe Savant::Workflow::Loader do
  it 'loads a valid workflow with tool and agent steps' do
    Dir.mktmpdir('savant-workflow-loader') do |tmp|
      wf_dir = File.join(tmp, 'workflows')
      FileUtils.mkdir_p(wf_dir)
      yaml = <<~YAML
        steps:
          - name: diff
            tool: git.diff
          - name: summarize
            agent: summarizer
            with:
              goal: "Summarize the diff concisely"
      YAML
      File.write(File.join(wf_dir, 'sample.yaml'), yaml)

      loader = described_class.new(base_path: tmp)
      spec = loader.load('sample')
      expect(spec[:id]).to eq('sample')
      expect(spec[:steps].length).to eq(2)
      expect(spec[:steps][0]).to include(name: 'diff', type: :tool, ref: 'git.diff')
      expect(spec[:steps][1]).to include(name: 'summarize', type: :agent, ref: 'summarizer')
      expect(spec[:steps][1][:with]).to eq({ 'goal' => 'Summarize the diff concisely' })
    end
  end

  it 'raises LoadError when workflow file is missing' do
    Dir.mktmpdir('savant-workflow-loader-missing') do |tmp|
      loader = described_class.new(base_path: tmp)
      expect { loader.load('missing') }.to raise_error(Savant::Workflow::Loader::LoadError, /not found/i)
    end
  end

  it 'raises LoadError on invalid YAML shape or missing fields' do
    Dir.mktmpdir('savant-workflow-loader-invalid') do |tmp|
      wf_dir = File.join(tmp, 'workflows')
      FileUtils.mkdir_p(wf_dir)
      # Missing name and tool/agent
      bad = <<~YAML
        steps:
          - {}
      YAML
      File.write(File.join(wf_dir, 'bad.yaml'), bad)

      loader = described_class.new(base_path: tmp)
      expect { loader.load('bad') }.to raise_error(Savant::Workflow::Loader::LoadError)
    end
  end
end

