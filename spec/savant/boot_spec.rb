#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require_relative '../../lib/savant/framework/boot'

RSpec.describe Savant::Boot do
  let(:test_base_path) { Dir.mktmpdir('savant-boot-test') }

  before do
    # Create required directory structure
    FileUtils.mkdir_p(File.join(test_base_path, 'lib', 'savant', 'engines', 'personas'))
    FileUtils.mkdir_p(File.join(test_base_path, 'lib', 'savant', 'engines', 'think', 'prompts'))
    FileUtils.mkdir_p(File.join(test_base_path, 'lib', 'savant', 'engines', 'amr'))
    FileUtils.mkdir_p(File.join(test_base_path, 'logs'))

    # Create test personas.yml
    personas_yml = <<~YAML
      ---
      - name: test-persona
        version: 1
        summary: Test persona
        prompt_md: Test prompt
        tags:
          - test
    YAML
    File.write(File.join(test_base_path, 'lib', 'savant', 'engines', 'personas', 'personas.yml'), personas_yml)

    # Create test prompts.yml
    prompts_yml = <<~YAML
      versions:
        test-v1: prompts/test.md
    YAML
    File.write(File.join(test_base_path, 'lib', 'savant', 'engines', 'think', 'prompts.yml'), prompts_yml)

    # Create test driver prompt
    File.write(File.join(test_base_path, 'lib', 'savant', 'engines', 'think', 'prompts', 'test.md'), 'Test driver prompt')

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
    File.write(File.join(test_base_path, 'lib', 'savant', 'engines', 'amr', 'rules.yml'), amr_yml)

    # Reset global runtime
    Savant::Framework::Runtime.current = nil
  end

  after do
    FileUtils.rm_rf(test_base_path)
    Savant::Framework::Runtime.current = nil
  end

  describe '.initialize!' do
    it 'successfully boots the runtime with all components' do
      context = described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      expect(context).to be_a(Savant::RuntimeContext)
      expect(context.session_id).to match(/^session_\d{8}_\d{6}_[a-f0-9]{8}$/)

      # Check persona loaded
      expect(context.persona).to be_a(Hash)
      expect(context.persona[:name]).to eq('test-persona')
      expect(context.persona[:version]).to eq(1)

      # Check driver prompt loaded
      expect(context.driver_prompt).to be_a(Hash)
      expect(context.driver_prompt[:version]).to eq('test-v1')
      expect(context.driver_prompt[:prompt_md]).to eq('Test driver prompt')

      # Check AMR rules loaded
      expect(context.amr_rules).to be_a(Hash)
      expect(context.amr_rules[:version]).to eq(1)
      expect(context.amr_rules[:rules]).to be_an(Array)
      expect(context.amr_rules[:rules].size).to eq(1)

      # Check memory initialized
      expect(context.memory).to be_a(Hash)
      expect(context.memory[:session_id]).to eq(context.session_id)
      expect(context.memory[:persistent_path]).to include('.savant/runtime.json')

      # Check logger exists
      expect(context.logger).to be_a(Savant::Logging::Logger)

      # Check repo is nil when skip_git is true
      expect(context.repo).to be_nil
    end

    it 'sets the global runtime context' do
      context = described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      expect(Savant::Framework::Runtime.current).to eq(context)
    end

    it 'creates .savant directory and runtime.json' do
      described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      savant_dir = File.join(test_base_path, '.savant')
      runtime_file = File.join(savant_dir, 'runtime.json')

      expect(File.directory?(savant_dir)).to be true
      expect(File.exist?(runtime_file)).to be true

      # Check runtime.json content
      runtime_data = JSON.parse(File.read(runtime_file))
      expect(runtime_data['session_id']).to match(/^session_/)
      expect(runtime_data['persona']['name']).to eq('test-persona')
      expect(runtime_data['driver_prompt']['version']).to eq('test-v1')
      expect(runtime_data['amr']['version']).to eq(1)
    end

    it 'creates boot log file' do
      described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      log_file = File.join(test_base_path, 'logs', 'engine_boot.log')
      expect(File.exist?(log_file)).to be true

      # Check log contains boot events
      log_content = File.read(log_file)
      expect(log_content).to include('boot_start')
      expect(log_content).to include('boot_complete')
    end

    it 'raises BootError when persona not found' do
      expect do
        described_class.initialize!(
          base_path: test_base_path,
          persona_name: 'nonexistent-persona',
          skip_git: true
        )
      end.to raise_error(Savant::Boot::BootError, /Failed to load persona/)
    end

    it 'raises BootError when AMR rules file missing' do
      FileUtils.rm(File.join(test_base_path, 'lib', 'savant', 'engines', 'amr', 'rules.yml'))

      expect do
        described_class.initialize!(
          base_path: test_base_path,
          persona_name: 'test-persona',
          skip_git: true
        )
      end.to raise_error(Savant::Boot::BootError, /AMR rules file not found/)
    end

    it 'raises BootError when AMR rules YAML is invalid' do
      File.write(File.join(test_base_path, 'lib', 'savant', 'engines', 'amr', 'rules.yml'), 'invalid: [yaml')

      expect do
        described_class.initialize!(
          base_path: test_base_path,
          persona_name: 'test-persona',
          skip_git: true
        )
      end.to raise_error(Savant::Boot::BootError, /Failed to parse AMR rules/)
    end

    context 'with git repository' do
      before do
        # Initialize a test git repo
        Dir.chdir(test_base_path) do
          `git init -q`
          `git config user.email "test@example.com"`
          `git config user.name "Test User"`
          `git checkout -b main 2>/dev/null || git checkout -b master`
          File.write('test.txt', 'test')
          `git add test.txt`
          `git commit -q -m "Initial commit"`
        end
      end

      it 'detects git repository context when not skipping' do
        Dir.chdir(test_base_path) do
          context = described_class.initialize!(
            base_path: test_base_path,
            persona_name: 'test-persona',
            skip_git: false
          )

          expect(context.repo).not_to be_nil
          # Use File.realpath to handle macOS /private symlink
          expect(File.realpath(context.repo[:path])).to eq(File.realpath(test_base_path))
          expect(context.repo[:branch]).to match(/^(main|master)$/)
          expect(context.repo[:last_commit]).to match(/^[a-f0-9]{7}$/)
        end
      end
    end
  end

  describe 'session ID generation' do
    it 'generates unique session IDs' do
      context1 = described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      # Small delay to ensure different timestamp
      sleep 0.1

      # Reset runtime
      Savant::Framework::Runtime.current = nil

      context2 = described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      expect(context1.session_id).not_to eq(context2.session_id)
    end
  end

  describe 'memory persistence' do
    it 'persists runtime state across multiple boots' do
      # First boot
      context1 = described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      runtime_file = File.join(test_base_path, '.savant', 'runtime.json')
      first_data = JSON.parse(File.read(runtime_file))

      # Reset runtime
      Savant::Framework::Runtime.current = nil
      sleep 0.1

      # Second boot
      context2 = described_class.initialize!(
        base_path: test_base_path,
        persona_name: 'test-persona',
        skip_git: true
      )

      second_data = JSON.parse(File.read(runtime_file))

      # Session IDs should be different
      expect(first_data['session_id']).not_to eq(second_data['session_id'])
      expect(context1.session_id).not_to eq(context2.session_id)

      # But both should have persisted
      expect(File.exist?(runtime_file)).to be true
    end
  end
end
