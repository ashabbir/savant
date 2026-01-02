# frozen_string_literal: true

require 'spec_helper'
require 'savant/reasoning/client'
require 'redis'
require 'json'

# Simple mock redis for testing basic queue ops
class MockRedis
  def initialize
    @data = {}
    @lists = Hash.new { |h, k| h[k] = [] }
  end

  def rpush(key, value)
    @lists[key] << value
    1
  end

  def blpop(key, timeout: 0)
    # Return nil immediately if empty for test simplicity, or pop first
    return nil if @lists[key].empty?
    
    [key, @lists[key].shift]
  end
  
  def lpop(key)
    @lists[key].shift
  end
  
  def get(key)
    @data[key]
  end
  
  def set(key, value)
    @data[key] = value
  end
end

RSpec.describe Savant::Reasoning::Client do
  let(:mock_redis) { MockRedis.new }
  let(:client) { described_class.new }

  before do
    allow(::Redis).to receive(:new).and_return(mock_redis)
    # Ensure client uses our mock
    allow(client).to receive(:redis_client).and_return(mock_redis)
  end

  describe '#agent_intent' do
    it 'pushes a job to Redis queue and waits for result' do
      payload = { session_id: 's1', persona: {}, goal_text: 'hi' }
      
      # Mock the blpop to return a result when called
      # We need to simulate the worker: client PUSHES -> worker PROCESSES -> client POPS
      # Since this is sync, we'll spy on rpush and then mock return of blpop
      
      expect(mock_redis).to receive(:rpush).with('savant:queue:reasoning', anything).and_call_original
      
      # Mock the response that would come back on the result key
      # The client generates a random job_id, so we can't key off it easily in setup without capturing it.
      # Instead, we just trust the client logic and verify flow.
      # To test fully, we can allow the client to call blpop and return a canned response.
      
      success_response = JSON.generate({
        status: 'ok',
        intent_id: 'test-redis-1',
        tool_name: nil,
        finish: true,
        final_text: 'redis done',
        reasoning: 'mocked'
      })
      
      allow(mock_redis).to receive(:blpop).and_return(['savant:result:xyz', success_response])
      
      intent = client.agent_intent(payload)
      
      expect(intent).to be_a(Savant::Reasoning::Intent)
      expect(intent.finish).to eq(true)
      expect(intent.final_text).to eq('redis done')
    end

    it 'raises error on timeout (nil from blpop)' do
      allow(mock_redis).to receive(:blpop).and_return(nil)
      
      expect do
        client.agent_intent({ session_id: 's1', goal_text: 'timeout me' })
      end.to raise_error(StandardError, /timeout/)
    end

    it 'raises error if result status is error' do
       error_response = JSON.generate({ status: 'error', error: 'worker crashed' })
       allow(mock_redis).to receive(:blpop).and_return(['key', error_response])
       
       expect do
         client.agent_intent({ session_id: 's1', goal_text: 'crash me' })
       end.to raise_error(StandardError, /worker crashed/)
    end
  end

  describe '#agent_intent_async' do
    it 'pushes job and returns accepted status immediately' do
      payload = { session_id: 'a1', goal_text: 'async' }
      callback = 'http://localhost/cb'
      
      expect(mock_redis).to receive(:rpush).with('savant:queue:reasoning', anything)
      
      res = client.agent_intent_async(payload, callback_url: callback)
      
      expect(res[:status]).to eq('accepted')
      expect(res[:job_id]).to match(/^agent-\d+/)
    end

    it 'raises if callback_url is missing' do
      expect do
        client.agent_intent_async({}, callback_url: nil)
      end.to raise_error(StandardError, /callback_url_required/)
    end
  end
end
