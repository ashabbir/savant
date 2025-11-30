# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/savant/engines/personas/tools'
require_relative '../../../../lib/savant/engines/personas/engine'

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
    expect(get[:name] || get['name']).to eq('savant-engineer')
    expect((get[:prompt_md] || get['prompt_md']).to_s).to include('Savant Engineer')
  end
end

RSpec.describe 'Hub includes mount for engines' do
  it 'returns mount path in hub root for FE compatibility' do
    # Build a router with a fake service manager for personas
    fm = Class.new do
      def initialize
        @start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def service = 'personas'
      def uptime = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start).to_i
      def service_info = { name: 'personas', version: '1.0.0' }
      def specs = [{ name: 'personas.list' }, { name: 'personas.get' }]
    end
    mounts = { 'personas' => fm.new }
    app = Savant::Hub::Router.build(mounts: mounts, transport: 'http')
    res = Rack::MockRequest.new(app).get('/', 'HTTP_X_SAVANT_USER_ID' => 't')
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    row = body['engines'].find { |e| e['name'] == 'personas' }
    expect(row).not_to be_nil
    # both keys should be present for backward compat
    expect(row['path']).to eq('/personas')
    expect(row['mount']).to eq('/personas')
    expect(row['tools']).to be >= 2
  end
end
