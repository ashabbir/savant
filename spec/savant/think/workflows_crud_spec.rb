# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe 'Think workflows CRUD (graph)' do
  let(:tmp_root) { Dir.mktmpdir('savant-think') }
  after do
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  def engine
    Savant::Think::Engine.new(env: { 'SAVANT_PATH' => tmp_root })
  end

  it 'creates, updates, validates and deletes workflows from graph' do
    g = {
      'nodes' => [
        { 'id' => 'get_user', 'call' => 'users/find', 'deps' => [] },
        { 'id' => 'merge', 'call' => 'prompt.say', 'deps' => ['get_user'], 'input_template' => { 'text' => 'done' } }
      ],
      'edges' => [{ 'source' => 'get_user', 'target' => 'merge' }]
    }
    v = engine.workflows_validate_graph(graph: g)
    expect(v[:ok]).to eq(true), v[:errors].inspect

    res = engine.workflows_create_from_graph(workflow: 'wf1', graph: g)
    expect(res[:ok]).to eq(true)
    pth = File.join(tmp_root, 'lib', 'savant', 'think', 'workflows', 'wf1.yaml')
    expect(File).to exist(pth)

    g2 = g.dup
    g2['nodes'] = g2['nodes'].map(&:dup)
    g2['nodes'][1]['input_template'] = { 'text' => 'updated' }
    up = engine.workflows_update_from_graph(workflow: 'wf1', graph: g2)
    expect(up[:ok]).to eq(true)

    rd = engine.workflows_read(workflow: 'wf1')
    expect(rd[:workflow_yaml]).to include('updated')

    del = engine.workflows_delete(workflow: 'wf1')
    expect(del[:ok]).to eq(true)
    expect(File).not_to exist(pth)
  end
end
