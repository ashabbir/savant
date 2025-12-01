require 'yaml'
require_relative '../../lib/savant/engines/workflow/loader'

RSpec.describe Savant::Workflow::Loader do
  let(:tmp_root) { Dir.mktmpdir('savant-workflow') }

  before do
    FileUtils.mkdir_p(File.join(tmp_root, 'workflows'))
    File.write(File.join(tmp_root, 'workflows', 'wf1.yaml'), <<~YAML)
      steps:
        - name: diff
          tool: git.diff
        - name: summarize
          agent: summarizer
          with:
            goal: "Summarize diff {{ diff }}"
    YAML
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SAVANT_PATH').and_return(tmp_root)
  end

  it 'loads a workflow YAML into normalized spec' do
    spec = described_class.load(tmp_root, 'wf1')
    expect(spec[:id]).to eq('wf1')
    expect(spec[:steps].length).to eq(2)
    expect(spec[:steps][0]).to include(name: 'diff', type: :tool, ref: 'git.diff')
    expect(spec[:steps][1]).to include(name: 'summarize', type: :agent, ref: 'summarizer')
  end
end

