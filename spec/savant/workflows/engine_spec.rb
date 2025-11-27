# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'savant/workflows/engine'

RSpec.describe 'Workflows Engine' do
  let(:tmp_root) { Dir.mktmpdir('savant-wf') }
  after do
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  def engine
    Savant::Workflows::Engine.new(env: { 'SAVANT_PATH' => tmp_root })
  end

  it 'creates, reads, lists and deletes workflows' do
    g = {
      'nodes' => [
        { 'id' => 'get_user', 'type' => 'tool', 'data' => { 'engine' => 'users', 'method' => 'find', 'args' => { 'id' => '{{ input.userId }}' } } },
        { 'id' => 'get_orders', 'type' => 'tool', 'data' => { 'engine' => 'orders', 'method' => 'listForUser', 'args' => { 'userId' => '{{ get_user.data.id }}' } } },
        { 'id' => 'merge', 'type' => 'llm', 'data' => { 'prompt' => 'Combine user and orders.' } }
      ],
      'edges' => [
        { 'source' => 'get_user', 'target' => 'get_orders' },
        { 'source' => 'get_orders', 'target' => 'merge' }
      ]
    }

    res = engine.create(id: 'fetch_user', graph: g)
    expect(res[:ok]).to eq(true)
    path = File.join(tmp_root, 'workflows', 'fetch_user.yaml')
    expect(File).to exist(path)

    rd = engine.read(id: 'fetch_user')
    expect(rd[:yaml]).to include('id: fetch_user')
    expect(rd[:graph]).to be_a(Hash)
    expect(rd[:graph]['nodes'].length).to eq(3)

    lst = engine.list
    ids = lst[:workflows].map { |w| w[:id] }
    expect(ids).to include('fetch_user')

    del = engine.delete(id: 'fetch_user')
    expect(del[:ok]).to eq(true)
    expect(File).not_to exist(path)
  end

  it 'rejects cycles and disconnected graphs' do
    g_cycle = {
      'nodes' => [
        { 'id' => 'a', 'type' => 'llm', 'data' => { 'prompt' => 'x' } },
        { 'id' => 'b', 'type' => 'return', 'data' => { 'value' => 'ok' } }
      ],
      'edges' => [
        { 'source' => 'a', 'target' => 'b' },
        { 'source' => 'b', 'target' => 'a' }
      ]
    }
    v = engine.validate(graph: g_cycle)
    expect(v[:ok]).to eq(false)
    expect(v[:errors].join(','))
      .to match(/cycles not allowed|graph must have exactly one start/)

    g_disc = {
      'nodes' => [
        { 'id' => 'a', 'type' => 'llm', 'data' => { 'prompt' => 'x' } },
        { 'id' => 'b', 'type' => 'return', 'data' => { 'value' => 'ok' } }
      ],
      'edges' => []
    }
    v2 = engine.validate(graph: g_disc)
    expect(v2[:ok]).to eq(false)
    expect(v2[:errors].join(',')).to include('graph must have exactly one start node')
  end
end
