#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'CLI Boot Commands', type: :integration do
  let(:bin_path) { File.expand_path('../../../bin/savant', __dir__) }
  let(:test_dir) { Dir.mktmpdir('savant-cli-test') }

  before do
    # Set SAVANT_PATH to test directory
    @original_savant_path = ENV['SAVANT_PATH']
    ENV['SAVANT_PATH'] = test_dir

    # Create required directory structure
    FileUtils.mkdir_p(File.join(test_dir, 'lib', 'savant', 'engines', 'personas'))
    FileUtils.mkdir_p(File.join(test_dir, 'lib', 'savant', 'engines', 'think', 'prompts'))
    FileUtils.mkdir_p(File.join(test_dir, 'lib', 'savant', 'engines', 'amr'))
    FileUtils.mkdir_p(File.join(test_dir, 'logs'))

    # Create test personas.yml (using actual project location for now)
    project_root = File.expand_path('../../..', __dir__)
    personas_source = File.join(project_root, 'lib', 'savant', 'engines', 'personas', 'personas.yml')
    if File.exist?(personas_source)
      FileUtils.cp(personas_source, File.join(test_dir, 'lib', 'savant', 'engines', 'personas', 'personas.yml'))
    else
      # Fallback: create minimal personas.yml
      personas_yml = <<~YAML
        ---
        - name: savant-engineer
          version: 1
          summary: Test engineer persona
          prompt_md: Test prompt
      YAML
      File.write(File.join(test_dir, 'lib', 'savant', 'engines', 'personas', 'personas.yml'), personas_yml)
    end

    # Create test prompts.yml and prompt file
    prompts_yml = <<~YAML
      versions:
        stable-2025-11: prompts/stable.md
    YAML
    File.write(File.join(test_dir, 'lib', 'savant', 'engines', 'think', 'prompts.yml'), prompts_yml)
    File.write(File.join(test_dir, 'lib', 'savant', 'engines', 'think', 'prompts', 'stable.md'), 'Test driver prompt')

    # Create test AMR rules
    amr_yml = <<~YAML
      version: 1
      description: Test AMR rules
      rules:
        - id: test-rule
          pattern: test
          action: test_action
          priority: high
    YAML
    File.write(File.join(test_dir, 'lib', 'savant', 'engines', 'amr', 'rules.yml'), amr_yml)
  end

  after do
    ENV['SAVANT_PATH'] = @original_savant_path
    FileUtils.rm_rf(test_dir)
  end

  def run_command(cmd)
    stdout, stderr, status = Open3.capture3(cmd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  describe 'savant run' do
    it 'successfully boots the engine' do
      result = run_command("#{bin_path} run --skip-git")

      expect(result[:status].success?).to be true
      expect(result[:stdout]).to include('Booting Savant Engine')
      expect(result[:stdout]).to include('Boot successful')
      expect(result[:stdout]).to include('Session ID:')
      expect(result[:stdout]).to include('Persona:')
      expect(result[:stdout]).to include('savant-engineer')
      expect(result[:stdout]).to include('Driver:')
      expect(result[:stdout]).to include('AMR Rules:')
      expect(result[:stdout]).to include('Engine ready for agent execution')
    end

    it 'creates .savant/runtime.json' do
      run_command("#{bin_path} run --skip-git")

      runtime_file = File.join(test_dir, '.savant', 'runtime.json')
      expect(File.exist?(runtime_file)).to be true

      runtime_data = JSON.parse(File.read(runtime_file))
      expect(runtime_data['session_id']).to match(/^session_/)
      expect(runtime_data['persona']['name']).to eq('savant-engineer')
    end

    it 'creates logs/engine_boot.log' do
      run_command("#{bin_path} run --skip-git")

      log_file = File.join(test_dir, 'logs', 'engine_boot.log')
      expect(File.exist?(log_file)).to be true

      log_content = File.read(log_file)
      expect(log_content).to include('boot_start')
      expect(log_content).to include('boot_complete')
    end

    it 'fails gracefully when persona not found' do
      result = run_command("#{bin_path} run --persona=nonexistent --skip-git")

      expect(result[:status].success?).to be false
      expect(result[:stderr]).to include('Boot failed')
      expect(result[:stderr]).to include('persona')
    end
  end

  describe 'savant review' do
    it 'successfully boots for review' do
      result = run_command("#{bin_path} review")

      expect(result[:status].success?).to be true
      expect(result[:stdout]).to include('Booting Savant Engine for MR Review')
      expect(result[:stdout]).to include('Boot successful')
      expect(result[:stdout]).to include('MR Review logic not yet implemented')
    end
  end

  describe 'savant workflow' do
    it 'successfully boots for workflow execution' do
      result = run_command("#{bin_path} workflow test-workflow --params='{}'")

      expect(result[:status].success?).to be true
      expect(result[:stdout]).to include('Booting Savant Engine for Workflow Execution')
      expect(result[:stdout]).to include('Boot successful')
      expect(result[:stdout]).to include('Workflow:')
      expect(result[:stdout]).to include('test-workflow')
      expect(result[:stdout]).to include('Workflow execution logic not yet implemented')
    end

    it 'requires workflow name' do
      result = run_command("#{bin_path} workflow")

      expect(result[:status].success?).to be false
      expect(result[:stderr]).to include('usage:')
    end
  end
end
