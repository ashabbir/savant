# frozen_string_literal: true

require 'spec_helper'
require 'webrick'
require 'savant/reasoning/client'

RSpec.describe Savant::Reasoning::Client do
  def with_server(port: 9299)
    server = WEBrick::HTTPServer.new(Port: port, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    thr = Thread.new { server.start }
    begin
      yield server
    ensure
      server.shutdown
      thr.join
    end
  end

  it 'posts to /agent_intent and returns an Intent' do
    with_server do |srv|
      srv.mount_proc '/agent_intent' do |req, res|
        JSON.parse(req.body)
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate({
                                   status: 'ok',
                                   intent_id: 'test-1',
                                   tool_name: nil,
                                   tool_args: {},
                                   finish: true,
                                   final_text: 'done',
                                   reasoning: 'stub'
                                 })
      end
      client = described_class.new(base_url: 'http://127.0.0.1:9299')
      intent = client.agent_intent({ session_id: 's1', persona: {}, goal_text: 'hi' })
      expect(intent).to be_a(Savant::Reasoning::Intent)
      expect(intent.finish).to eq(true)
      expect(intent.final_text).to eq('done')
    end
  end

  it 'retries on 500 and then succeeds' do
    hits = 0
    with_server do |srv|
      srv.mount_proc '/agent_intent' do |_req, res|
        hits += 1
        if hits == 1
          res.status = 500
          res.body = 'error'
        else
          res['Content-Type'] = 'application/json'
          res.body = JSON.generate({ status: 'ok', intent_id: 'retry-ok', finish: true })
        end
      end
      client = described_class.new(base_url: 'http://127.0.0.1:9299', retries: 1)
      intent = client.agent_intent({ session_id: 's1', persona: {}, goal_text: 'hi' })
      expect(intent.intent_id).to eq('retry-ok')
    end
  end

  it 'raises on timeout after retries' do
    with_server do |srv|
      srv.mount_proc '/agent_intent' do |_req, res|
        sleep 0.2
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate({ status: 'ok', intent_id: 'late', finish: true })
      end
      client = described_class.new(base_url: 'http://127.0.0.1:9299', timeout_ms: 50, retries: 0)
      expect do
        client.agent_intent({ session_id: 's1', persona: {}, goal_text: 'hi' })
      end.to raise_error(StandardError, /timeout/)
    end
  end
end
