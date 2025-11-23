# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/personas/tools'
require_relative '../../../lib/savant/personas/engine'

RSpec.describe Savant::Personas::Tools do
  it 'exposes personas.list and personas.get tools' do
    engine = Savant::Personas::Engine.new
    reg = described_class.build_registrar(engine)
    names = reg.specs.map { |s| s[:name] }
    expect(names).to include('personas.list')
    expect(names).to include('personas.get')

    list = reg.call('personas.list', { 'filter' => 'savant' }, ctx: { engine: engine })
    expect(list).to be_a(Hash)
    expect(list[:personas] || list['personas']).to be_a(Array)

    get = reg.call('personas.get', { 'name' => 'savant-engineer' }, ctx: { engine: engine })
    expect((get[:name] || get['name'])).to eq('savant-engineer')
    expect((get[:prompt_md] || get['prompt_md']).to_s).to include('Savant Engineer')
  end
end
