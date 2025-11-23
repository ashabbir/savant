# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/rules/tools'
require_relative '../../../lib/savant/rules/engine'

RSpec.describe Savant::Rules::Tools do
  it 'exposes rules.list and rules.get tools' do
    engine = Savant::Rules::Engine.new
    reg = described_class.build_registrar(engine)
    names = reg.specs.map { |s| s[:name] }
    expect(names).to include('rules.list', 'rules.get')

    list = reg.call('rules.list', { 'filter' => 'rules' }, ctx: { engine: engine })
    expect(list).to be_a(Hash)
    expect(list[:rules] || list['rules']).to be_a(Array)

    get = reg.call('rules.get', { 'name' => 'code-review-rules' }, ctx: { engine: engine })
    expect(get[:name] || get['name']).to eq('code-review-rules')
    expect((get[:rules_md] || get['rules_md']).to_s).to include('Code Review Rules')
  end
end
