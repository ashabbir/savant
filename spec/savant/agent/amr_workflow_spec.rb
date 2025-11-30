require 'tmpdir'
require_relative '../../../lib/savant/agent/runtime'
require_relative '../../../lib/savant/framework/engine/runtime_context'

RSpec.describe 'Agent AMR workflow shortcut' do
  let(:tmp_root) { Dir.mktmpdir('savant-amr-wf') }

  before do
    FileUtils.mkdir_p(File.join(tmp_root, 'workflows'))
    File.write(File.join(tmp_root, 'workflows', 'hello.yaml'), "steps:\n  - name: greet\n    agent: summarizer\n")
    Savant::Framework::Runtime.current = Savant::RuntimeContext.new(
      session_id: 't', persona: {}, driver_prompt: {}, amr_rules: {}, repo: nil, memory: {}, logger: nil, multiplexer: nil
    )
  end

  it 'auto-triggers workflow.run when goal includes workflow name' do
    agent = Savant::Agent::Runtime.new(goal: 'please run workflow hello to greet me', base_path: tmp_root)
    res = agent.run(max_steps: 2, dry_run: true)
    expect(res[:status]).to eq('ok')
    expect(res[:final]).to include('Finished after workflow.workflow.run')
  end
end

