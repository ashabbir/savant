# frozen_string_literal: true

require 'spec_helper'
require 'savant/framework/engine/engine'

RSpec.describe 'Savant::Framework::Engine::Base lifecycle hooks' do
  it 'runs before and after hooks around tool execution in order' do
    # Dummy engine with hooks capturing order
    klass = Class.new(Savant::Framework::Engine::Base) do
      def initialize
        super()
        @events = []
      end

      attr_reader :events

      before_call :auth
      after_call  :audit

      private

      def auth(ctx, payload)
        @events << [:before, ctx[:tool], payload]
      end

      def audit(ctx, payload)
        @events << [:after, ctx[:tool], payload]
      end
    end

    engine = klass.new

    # Fake registrar chain: middleware calls engine.wrap_call
    tool_handler = proc { |_ctx, a| [:ok, a] }
    call = proc do |ctx, name, args|
      engine.wrap_call(ctx, name, args) { tool_handler.call(ctx, args) }
    end

    ctx = { tool: 'test/echo', request_id: '1' }
    out = call.call(ctx, 'test/echo', { 'msg' => 'hi' })

    expect(out).to eq([:ok, { 'msg' => 'hi' }])
    expect(engine.events.map(&:first)).to eq(%i[before after])
    expect(engine.events[0]).to eq([:before, 'test/echo', { 'msg' => 'hi' }])
    expect(engine.events[1]).to eq([:after, 'test/echo', { 'msg' => 'hi' }])
  end
end
