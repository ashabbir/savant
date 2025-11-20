# frozen_string_literal: true

require_relative '../../lib/savant/secret_store'

RSpec.describe Savant::SecretStore do
  before do
    described_class.reset!
  end

  it 'stores and retrieves secrets per user and service' do
    described_class.set('u1', :jira, :api_token, 'token-u1')
    described_class.set('u2', :jira, :api_token, 'token-u2')

    expect(described_class.get('u1', :jira, :api_token)).to eq('token-u1')
    expect(described_class.get('u2', :jira, :api_token)).to eq('token-u2')
  end

  it 'sanitizes secret-like values from hashes' do
    data = { token: 'secret', api_key: 'abc', nested: { password: 'pw' } }
    scrubbed = described_class.sanitize(data)
    expect(scrubbed[:token]).to eq('[REDACTED]')
    expect(scrubbed[:api_key]).to eq('[REDACTED]')
    expect(scrubbed[:nested][:password]).to eq('[REDACTED]')
  end
end

