# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/personas/tools'

RSpec.describe Savant::Personas::Tools do
  it 'builds registrar with example tool' do
    engine = double('engine')
    reg = described_class.build_registrar(engine)
    specs = reg.specs
    expect(specs.any? { |s| s[:name] == 'personas/hello' }).to be(true)
    out = reg.call('personas/hello', { 'name' => 'dev' }, ctx: { engine: engine })
    expect(out).to eq({ hello: 'dev' })
  end
end
