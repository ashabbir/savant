# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/savant/engines/think/engine'

RSpec.describe 'Think workflow graph validation' do
  let(:engine) { Savant::Think::Engine.new(env: {}) }

  it 'accepts a minimal valid graph' do
    graph = {
      'nodes' => [
        { 'id' => '1', 'call' => 'prompt_say' },
        { 'id' => '2', 'call' => 'prompt_say', 'deps' => ['1'] }
      ]
    }
    res = engine.workflows_validate_graph(graph: graph)
    expect(res[:ok]).to be true
    expect(res[:errors]).to eq([])
  end

  it 'rejects duplicate ids' do
    graph = {
      'nodes' => [
        { 'id' => '1', 'call' => 'prompt_say' },
        { 'id' => '1', 'call' => 'prompt_say' }
      ]
    }
    res = engine.workflows_validate_graph(graph: graph)
    expect(res[:ok]).to be false
    expect(res[:errors].join(' ')).to match(/duplicate/i)
  end

  it 'rejects nodes missing call' do
    graph = {
      'nodes' => [
        { 'id' => '1', 'call' => 'prompt_say' },
        { 'id' => '2' }
      ]
    }
    res = engine.workflows_validate_graph(graph: graph)
    expect(res[:ok]).to be false
    expect(res[:errors].join(' ')).to match(/call missing/i)
  end

  it 'detects cycles / no start node' do
    graph = {
      'nodes' => [
        { 'id' => '1', 'call' => 'prompt_say', 'deps' => ['2'] },
        { 'id' => '2', 'call' => 'prompt_say', 'deps' => ['1'] }
      ]
    }
    res = engine.workflows_validate_graph(graph: graph)
    expect(res[:ok]).to be false
    msg = res[:errors].join(' ')
    expect(msg).to match(/start|cycle/i)
  end
end
