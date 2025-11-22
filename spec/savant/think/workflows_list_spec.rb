# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Savant Think workflows listing' do
  let(:tmp_root) { Dir.mktmpdir('savant_think_wf_list') }
  let(:workflows_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'workflows') }
  let(:prompts_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'prompts') }

  before do
    ENV['SAVANT_PATH'] = tmp_root
    FileUtils.mkdir_p(workflows_dir)
    FileUtils.mkdir_p(prompts_dir)

    # Valid workflow in .yml
    File.write(File.join(workflows_dir, 'valid_wf.yml'), <<~YAML)
      name: valid_wf
      version: "1.0"
      description: "Valid YAML workflow using .yml extension"
      steps:
        - id: one
          call: prompt.say
          input_template:
            text: "hello"
    YAML

    # Valid workflow in .yaml
    File.write(File.join(workflows_dir, 'another.yaml'), <<~YAML)
      name: another
      version: "2.0"
      description: "Valid YAML workflow using .yaml extension"
      steps:
        - id: a
          call: prompt.say
          input_template:
            text: "a"
    YAML

    # Corrupted workflow file that should be ignored by list
    File.open(File.join(workflows_dir, 'broken.yml'), 'wb') do |f|
      f.write("\xFF\xFE\x00\x00not-yaml\n")
    end

    # Prompts registry (required by engine for driver injection paths)
    File.write(File.join(tmp_root, 'lib', 'savant', 'think', 'prompts.yml'), <<~YAML)
      versions:
        stable-2025-11: prompts/stable-2025-11.md
    YAML
    File.write(File.join(prompts_dir, 'stable-2025-11.md'), "# Driver\n")
  end

  after do
    ENV.delete('SAVANT_PATH')
    FileUtils.rm_rf(tmp_root) if File.directory?(tmp_root)
  end

  it 'returns workflows list without crashing on invalid files' do
    require_relative '../../../lib/savant/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    list = registrar.call('think.workflows.list', { 'filter' => '' }, ctx: {})
    ids = list[:workflows].map { |w| w[:id] }
    expect(ids).to include('valid_wf', 'another')
    expect(ids).not_to include('broken')
  end

  it 'reads .yml workflows via workflows.read and loads via plan' do
    require_relative '../../../lib/savant/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    read = registrar.call('think.workflows.read', { 'workflow' => 'valid_wf' }, ctx: {})
    expect(read[:workflow_yaml]).to include('name: valid_wf')

    plan = registrar.call('think.plan', { 'workflow' => 'valid_wf', 'params' => {}, 'run_id' => 'r1', 'start_fresh' => true }, ctx: {})
    expect(plan[:instruction][:step_id]).to eq('__driver_bootstrap')
  end
end
