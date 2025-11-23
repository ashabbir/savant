# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Savant Think payload handling' do
  let(:tmp_root) { Dir.mktmpdir('savant_think_payload_spec') }
  let(:workflows_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'workflows') }
  let(:prompts_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'prompts') }
  let(:config_dir) { File.join(tmp_root, 'config') }

  before do
    ENV['SAVANT_PATH'] = tmp_root
    FileUtils.mkdir_p(workflows_dir)
    FileUtils.mkdir_p(prompts_dir)
    FileUtils.mkdir_p(config_dir)

    # Minimal workflow with a capture step
    File.write(File.join(workflows_dir, 'review_v1.yaml'), <<~YAML)
      name: review_v1
      version: "1.3"
      driver_version: "stable-2025-11"
      steps:
        - id: lint
          call: context.search
          input_template:
            q: "rubocop offenses"
          capture_as: lint_result
    YAML

    # Prompts registry and a single prompt version
    File.write(File.join(tmp_root, 'lib', 'savant', 'think', 'prompts.yml'), <<~YAML)
      versions:
        stable-2025-11: prompts/stable-2025-11.md
    YAML
    File.write(File.join(prompts_dir, 'stable-2025-11.md'), <<~MD)
      # Driver: Savant Think (Guide Mode)
      Always follow the loop.
    MD
  end

  after do
    ENV.delete('SAVANT_PATH')
    FileUtils.rm_rf(tmp_root) if File.directory?(tmp_root)
  end

  it 'sanitizes non-UTF8 snapshots and writes UTF-8 state' do
    require_relative '../../../lib/savant/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    # Plan -> driver bootstrap
    plan = registrar.call('think.plan', { 'workflow' => 'review_v1', 'params' => {}, 'run_id' => 'test-run', 'start_fresh' => true }, ctx: {})
    expect(plan[:instruction][:step_id]).to eq('__driver_bootstrap')

    # Advance driver steps
    registrar.call('think.next', {
                     'workflow' => 'review_v1', 'run_id' => 'test-run',
                     'step_id' => '__driver_bootstrap',
                     'result_snapshot' => { 'version' => 'stable-2025-11', 'prompt_md' => '...' }
                   }, ctx: {})
    nxt2 = registrar.call('think.next', {
                            'workflow' => 'review_v1', 'run_id' => 'test-run',
                            'step_id' => '__driver_announce',
                            'result_snapshot' => { 'ok' => true }
                          }, ctx: {})
    expect(nxt2[:instruction][:step_id]).to eq('lint')

    # Build a non-UTF8 snapshot (binary string with invalid bytes)
    bad = "abc\xFF\xFExyz".dup.force_encoding('ASCII-8BIT')
    snapshot = { 'text' => bad, 'list' => [bad] }

    # Submit snapshot; engine should sanitize and persist
    registrar.call('think.next', {
                     'workflow' => 'review_v1', 'run_id' => 'test-run',
                     'step_id' => 'lint',
                     'result_snapshot' => snapshot
                   }, ctx: {})

    state_path = File.join(tmp_root, '.savant', 'state', 'review_v1__test-run.json')
    expect(File).to exist(state_path)
    data = JSON.parse(File.read(state_path))
    val = data.dig('vars', 'lint_result')
    # Invalid bytes should be replaced; strings should be valid UTF-8 in JSON
    expect(val['text'].encoding.name).to eq('UTF-8')
  end

  it 'truncates large snapshots using think.yml limits' do
    # Configure very small limits to force truncation
    File.write(File.join(config_dir, 'think.yml'), <<~YAML)
      payload:
        max_snapshot_bytes: 64
        max_string_bytes: 16
      logging:
        log_payload_sizes: true
        warn_threshold_bytes: 40
    YAML

    require_relative '../../../lib/savant/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    plan = registrar.call('think.plan', { 'workflow' => 'review_v1', 'params' => {}, 'run_id' => 'test-run', 'start_fresh' => true }, ctx: {})
    expect(plan[:instruction][:step_id]).to eq('__driver_bootstrap')
    registrar.call('think.next', { 'workflow' => 'review_v1', 'run_id' => 'test-run', 'step_id' => '__driver_bootstrap', 'result_snapshot' => { 'version' => 'v', 'prompt_md' => '...' } }, ctx: {})
    registrar.call('think.next', { 'workflow' => 'review_v1', 'run_id' => 'test-run', 'step_id' => '__driver_announce', 'result_snapshot' => { 'ok' => true } }, ctx: {})

    big = 'X' * 10_000
    registrar.call('think.next', { 'workflow' => 'review_v1', 'run_id' => 'test-run', 'step_id' => 'lint', 'result_snapshot' => { 'big' => big } }, ctx: {})

    state_path = File.join(tmp_root, '.savant', 'state', 'review_v1__test-run.json')
    data = JSON.parse(File.read(state_path))
    val = data.dig('vars', 'lint_result', 'big')
    # Expect truncation marker or shortened content
    expect(val.length).to be <= 100 # within the configured limits after truncation
  end
end
