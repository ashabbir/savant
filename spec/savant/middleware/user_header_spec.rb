# frozen_string_literal: true

require 'json'
require 'rack/mock'

require_relative '../lib/savant/framework/middleware/user_header'

class EchoRackApp
  def call(env)
    user = env['savant.user_id']
    [200, { 'Content-Type' => 'application/json' }, [JSON.generate({ ok: true, user: user })]]
  end
end

RSpec.describe Savant::Framework::Middleware::UserHeader do
  let(:app) { described_class.new(EchoRackApp.new) }
  let(:request) { Rack::MockRequest.new(app) }

  it 'rejects requests without x-savant-user-id' do
    res = request.get('/')
    expect(res.status).to eq(400)
    expect(JSON.parse(res.body)['error']).to include('x-savant-user-id')
  end

  it 'attaches user id to env when present' do
    res = request.get('/', 'HTTP_X_SAVANT_USER_ID' => 'alice')
    expect(res.status).to eq(200)
    expect(JSON.parse(res.body)['user']).to eq('alice')
  end
end
