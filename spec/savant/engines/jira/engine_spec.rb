# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/savant/engines/jira/engine'

RSpec.describe Savant::Jira::Engine do
  let(:base_env) do
    {
      'JIRA_BASE_URL' => 'https://example.atlassian.net',
      'JIRA_EMAIL' => 'user@example.com',
      'JIRA_API_TOKEN' => 'token',
      'JIRA_USERNAME' => 'user',
      'JIRA_PASSWORD' => 'secret'
    }
  end

  let(:client) { double('Client', base_url: 'https://example.atlassian.net') }
  let(:ops) { double('Ops') }

  before do
    allow(Savant::Jira::Client).to receive(:new).and_return(client)
    allow(Savant::Jira::Ops).to receive(:new).with(client).and_return(ops)
  end

  describe '#initialize' do
    it 'raises when JIRA_BASE_URL is missing' do
      expect { described_class.new(env: {}) }.to raise_error(/JIRA_BASE_URL is required/)
    end

    it 'initializes client and ops with expected parameters' do
      described_class.new(env: base_env)

      expect(Savant::Jira::Client).to have_received(:new).with(
        base_url: 'https://example.atlassian.net',
        email: 'user@example.com',
        api_token: 'token',
        username: 'user',
        password: 'secret'
      )
      expect(Savant::Jira::Ops).to have_received(:new).with(client)
    end
  end

  describe '#search' do
    it 'delegates to ops with default fields' do
      env = base_env.merge('JIRA_ALLOW_WRITES' => 'false')
      engine = described_class.new(env: env)
      allow(ops).to receive(:search).and_return(%w[ISSUE-1])

      result = engine.search(jql: 'project=TEST', limit: 5, start_at: 2)

      expect(ops).to have_received(:search).with(
        jql: 'project=TEST',
        limit: 5,
        start_at: 2,
        fields: described_class::DEFAULT_FIELDS
      )
      expect(result).to eq(%w[ISSUE-1])
    end
  end

  describe '#self_test' do
    it 'calls the Jira client self endpoint' do
      env = base_env
      engine = described_class.new(env: env)
      allow(client).to receive(:get).with('/rest/api/3/myself').and_return('ok')

      expect(engine.self_test).to eq('ok')
    end
  end

  describe 'write guarded operations' do
    let(:payload) { { summary: 'Test' } }

    it 'raises when writes are disabled' do
      env = base_env
      engine = described_class.new(env: env)
      allow(ops).to receive(:create_issue)

      expect { engine.create_issue(**payload) }.to raise_error('writes disabled: set JIRA_ALLOW_WRITES=true')
      expect(ops).not_to have_received(:create_issue)
    end

    it 'delegates to ops when writes are enabled' do
      env = base_env.merge('JIRA_ALLOW_WRITES' => 'TrUe')
      engine = described_class.new(env: env)
      allow(ops).to receive(:create_issue).and_return('created')

      result = engine.create_issue(**payload)

      expect(result).to eq('created')
      expect(ops).to have_received(:create_issue).with(payload)
    end
  end

  describe 'read-only operations' do
    it 'delegates without requiring write access' do
      env = base_env
      engine = described_class.new(env: env)
      allow(ops).to receive(:download_attachments).with(issue_key: 'ABC-1').and_return(%w[file1 file2])

      result = engine.download_attachments(issue_key: 'ABC-1')

      expect(result).to eq(%w[file1 file2])
    end
  end
end
# !/usr/bin/env ruby
# frozen_string_literal: true
