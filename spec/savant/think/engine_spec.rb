# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Savant Think MCP' do
  let(:tmp_root) { Dir.mktmpdir('savant_think_spec') }
  let(:workflows_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'workflows') }
  let(:prompts_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'prompts') }

  before do
    # Prepare isolated SAVANT_PATH with workflows and prompts
    ENV['SAVANT_PATH'] = tmp_root
    FileUtils.mkdir_p(workflows_dir)
    FileUtils.mkdir_p(prompts_dir)

    # Minimal workflow for testing
    File.write(File.join(workflows_dir, 'review_v1.yaml'), <<~YAML)
      name: review_v1
      version: "1.0"
      steps:
        - id: lint
          call: context.search
          input_template:
            q: "rubocop offenses"
          capture_as: lint_result
        - id: tests
          call: ci.run_tests
          deps: ["lint"]
          input_template:
            ref: "{{params.branch}}"
    YAML

    # Prompts registry and a single prompt version
    File.write(File.join(tmp_root, 'lib', 'savant', 'think', 'prompts.yml'), <<~YAML)
      versions:
        stable-2025-11: prompts/stable-2025-11.md
    YAML

    File.write(File.join(prompts_dir, 'stable-2025-11.md'), <<~MD)
      # Driver: Savant Think (Guide Mode)
      Always follow the loop: plan → execute → next → repeat.
    MD
  end

  after do
    ENV.delete('SAVANT_PATH')
    FileUtils.rm_rf(tmp_root) if File.directory?(tmp_root)
  end

  it 'lists think tools via registrar and serves driver prompt' do
    expect do
      require_relative '../lib/savant/engines/think/tools'
    end.to_not raise_error

    registrar = Savant::Think::Tools.build_registrar(nil)
    tools = registrar.specs.map { |t| t[:name] || t['name'] }
    expect(tools).to include('think.driver_prompt', 'think.plan', 'think.next')

    # Call driver prompt and verify version/hash and content
    out = registrar.call('think.driver_prompt', { 'version' => 'stable-2025-11' }, ctx: {})
    expect(out).to include(:version, :hash, :prompt_md)
    expect(out[:version]).to eq('stable-2025-11')
    expect(out[:hash]).to start_with('sha256:')
    expect(out[:prompt_md]).to include('Driver: Savant Think')
  end

  it 'plans first instruction and advances deterministically' do
    require_relative '../lib/savant/engines/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    # Plan the workflow
    plan = registrar.call('think.plan', { 'workflow' => 'review_v1', 'params' => { 'branch' => 'main' }, 'run_id' => 't-run', 'start_fresh' => true }, ctx: {})
    expect(plan).to include(:instruction, :state, :done)
    expect(plan[:done]).to eq(false)
    # With driver injection, first instruction is driver bootstrap
    expect(plan[:instruction][:step_id]).to eq('__driver_bootstrap')
    expect(plan[:instruction][:call]).to eq('think.driver_prompt')

    # Advance driver bootstrap
    nxt1 = registrar.call('think.next', {
                            'workflow' => 'review_v1', 'run_id' => 't-run',
                            'step_id' => '__driver_bootstrap',
                            'result_snapshot' => { 'version' => 'stable-2025-11', 'prompt_md' => '...' }
                          }, ctx: {})
    expect(nxt1[:done]).to eq(false)
    expect(nxt1[:instruction][:step_id]).to eq('__driver_announce')
    expect(nxt1[:instruction][:call]).to eq('prompt.say')

    # Advance driver announce; expect actual first workflow step 'lint'
    nxt2 = registrar.call('think.next', {
                            'workflow' => 'review_v1', 'run_id' => 't-run',
                            'step_id' => '__driver_announce',
                            'result_snapshot' => { 'ok' => true }
                          }, ctx: {})
    expect(nxt2[:done]).to eq(false)
    expect(nxt2[:instruction][:step_id]).to eq('lint')
    expect(nxt2[:instruction][:call]).to eq('context.search')

    # Next: complete lint, expect tests
    nxt = registrar.call('think.next', {
                           'workflow' => 'review_v1', 'run_id' => 't-run',
                           'step_id' => 'lint',
                           'result_snapshot' => { 'rows' => [] }
                         }, ctx: {})
    expect(nxt[:done]).to eq(false)
    expect(nxt[:instruction][:step_id]).to eq('tests')
    expect(nxt[:instruction][:call]).to eq('ci.run_tests')

    # Next: complete tests, expect done summary
    fin = registrar.call('think.next', {
                           'workflow' => 'review_v1', 'run_id' => 't-run',
                           'step_id' => 'tests',
                           'result_snapshot' => { 'ok' => true }
                         }, ctx: {})
    expect(fin[:done]).to eq(true)
    expect(fin[:summary]).to be_a(String)

    # State file exists
    state_path = File.join(tmp_root, '.savant', 'state', 'review_v1__t-run.json')
    expect(File).to exist(state_path)
  end

  it 'lists and reads workflows' do
    require_relative '../lib/savant/engines/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    list = registrar.call('think.workflows.list', { 'filter' => 'review' }, ctx: {})
    ids = list[:workflows].map { |w| w[:id] }
    expect(ids).to include('review_v1')

    read = registrar.call('think.workflows.read', { 'workflow' => 'review_v1' }, ctx: {})
    expect(read[:workflow_yaml]).to include('name: review_v1')
  end
end
