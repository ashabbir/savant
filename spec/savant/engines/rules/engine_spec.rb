# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/savant/engines/rules/tools'
require_relative '../../../../lib/savant/engines/rules/engine'

RSpec.describe Savant::Rules::Tools do
  it 'exposes rules_list and rules_get tools' do
    engine = Savant::Rules::Engine.new
    reg = described_class.build_registrar(engine)
    names = reg.specs.map { |s| s[:name] }
    expect(names).to include('rules_list', 'rules_get', 'rules_create', 'rules_update', 'rules_delete', 'rules_read', 'rules_write', 'rules_catalog_read', 'rules_catalog_write')

    list = reg.call('rules_list', { 'filter' => 'rules' }, ctx: { engine: engine })
    expect(list).to be_a(Hash)
    expect(list[:rules] || list['rules']).to be_a(Array)

    get = reg.call('rules_get', { 'name' => 'code-review-rules' }, ctx: { engine: engine })
    expect(get[:name] || get['name']).to eq('code-review-rules')
    expect((get[:rules_md] || get['rules_md']).to_s).to include('Code Review Rules')
  end
end
