# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Savant Think step gating (applicable_when)' do
  let(:tmp_root) { Dir.mktmpdir('savant_think_gate_spec') }
  let(:workflows_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'workflows') }
  let(:prompts_dir) { File.join(tmp_root, 'lib', 'savant', 'think', 'prompts') }

  before do
    ENV['SAVANT_PATH'] = tmp_root
    FileUtils.mkdir_p(workflows_dir)
    FileUtils.mkdir_p(prompts_dir)

    # Workflow with a gate step and a conditional step controlled by applicable_when
    File.write(File.join(workflows_dir, 'gate_demo.yaml'), <<~YAML)
      name: gate_demo
      version: "1.0"
      driver_version: "stable-2025-11"
      steps:
        - id: gate_migrations
          call: prompt.say
          input_template:
            text: "Gate: analyze if migrations are applicable; return {applicable: bool, confidence: 0..1}"
          capture_as: gate_mig

        - id: run_migration_checks
          call: prompt.say
          deps: [gate_migrations]
          applicable_when:
            var: gate_mig
            field: applicable
            equals: true
            min_conf_field: confidence
            min_conf: 0.6
          input_template:
            text: "Run migration safety checks"

        - id: after_checks
          call: prompt.say
          deps: [run_migration_checks]
          input_template:
            text: "Continue after migration gating"
    YAML

    # Prompts registry and a single prompt version
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

  it 'skips conditional step when gate says not applicable with sufficient confidence' do
    require_relative '../../../lib/savant/think/tools'
    registrar = Savant::Think::Tools.build_registrar(nil)

    plan = registrar.call('think.plan', { 'workflow' => 'gate_demo', 'params' => {}, 'run_id' => 'g1', 'start_fresh' => true }, ctx: {})
    expect(plan[:instruction][:step_id]).to eq('__driver_bootstrap')

    # Advance driver steps
    registrar.call('think.next', { 'workflow' => 'gate_demo', 'run_id' => 'g1', 'step_id' => '__driver_bootstrap', 'result_snapshot' => { 'version' => 'stable-2025-11', 'prompt_md' => '...' } }, ctx: {})
    nxt = registrar.call('think.next', { 'workflow' => 'gate_demo', 'run_id' => 'g1', 'step_id' => '__driver_announce', 'result_snapshot' => { 'ok' => true } }, ctx: {})
    expect(nxt[:instruction][:step_id]).to eq('gate_migrations')

    # Submit gate result: not applicable with high confidence and expect the engine to skip the conditional step
    nxt2 = registrar.call('think.next', {
                           'workflow' => 'gate_demo', 'run_id' => 'g1', 'step_id' => 'gate_migrations',
                           'result_snapshot' => { 'applicable' => false, 'confidence' => 0.95 }
                         }, ctx: {})

    # Next instruction should skip run_migration_checks and proceed directly to after_checks
    expect(nxt2[:done]).to eq(false)
    expect(nxt2[:instruction][:step_id]).to eq('after_checks')
  end
end
