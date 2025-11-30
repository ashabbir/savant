require 'json'
require 'tmpdir'
require_relative '../../lib/savant/engines/workflow/engine'
require_relative '../../lib/savant/framework/engine/runtime_context'

RSpec.describe 'Workflow executor end-to-end' do
  class StubMux
    def call(name, args)
      case name
      when 'git.diff'
        { files: ['a.rb', 'b.rb'], hunks: [], args: args }
      when 'context.fts_search'
        { hits: [{ path: 'README.md', score: 1.0 }], query: args['q'] }
      else
        { ok: true, tool: name, args: args }
      end
    end
  end

  let(:tmp_root) { Dir.mktmpdir('savant-workflow-e2e') }

  before do
    FileUtils.mkdir_p(File.join(tmp_root, 'workflows'))
    # Tool-only workflow
    File.write(File.join(tmp_root, 'workflows', 'tool_only.yaml'), <<~YAML)
      steps:
        - name: diff
          tool: git.diff
    YAML
    # Mixed workflow
    File.write(File.join(tmp_root, 'workflows', 'mixed.yaml'), <<~YAML)
      steps:
        - name: diff
          tool: git.diff
        - name: cross
          tool: context.fts_search
          with:
            q: "{{ diff.files }}"
        - name: summarize
          agent: summarizer
          with:
            review: "{{ diff }}"
    YAML
    # Setup runtime with stub mux
    Savant::Framework::Runtime.current = Savant::RuntimeContext.new(
      session_id: 'test', persona: {}, driver_prompt: {}, amr_rules: {}, repo: nil, memory: {}, logger: nil, multiplexer: StubMux.new
    )
  end

  it 'runs a tool-only workflow' do
    eng = Savant::Workflow::Engine.new(base_path: tmp_root)
    res = eng.run(workflow: 'tool_only', params: {})
    expect(res[:status]).to eq('ok')
    state = eng.run_read(workflow: 'tool_only', run_id: res[:run_id])[:state]
    expect(state['steps']).not_to be_empty
  end

  it 'runs a mixed (tool + agent) workflow with stubbed agent' do
    eng = Savant::Workflow::Engine.new(base_path: tmp_root)
    res = eng.run(workflow: 'mixed', params: {})
    expect(res[:status]).to eq('ok')
    state = eng.run_read(workflow: 'mixed', run_id: res[:run_id])[:state]
    last = state['steps'].last
    expect(last).to be_a(Hash)
    # Since agent is stubbed by default, ensure mode is stub
    outputs = last['output'] || {}
    if outputs.is_a?(Hash)
      expect((outputs['mode'] || outputs[:mode]).to_s).to eq('stub')
    end
  end
end

