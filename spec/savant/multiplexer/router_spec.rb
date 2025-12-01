# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/multiplexer/router'

RSpec.describe Savant::Multiplexer::Router do
  it 'namespaces tools per engine' do
    router = described_class.new
    router.register('context', [{ name: 'fts_search', description: 'Search repos' }])
    router.register('jira', [{ 'name' => 'issue.get', 'description' => 'Get issue' }])

    names = router.tools.map { |spec| spec[:name] || spec['name'] }
    expect(names).to include('context.fts_search')
    expect(names).to include('jira.issue.get')
  end

  it 'removes tools when engine removed' do
    router = described_class.new
    router.register('context', [{ name: 'fts_search' }])
    router.remove('context')

    expect(router.tools).to be_empty
  end

  it 'resolves lookups' do
    router = described_class.new
    router.register('context', [{ name: 'fts_search' }])
    meta = router.lookup('context.fts_search')
    expect(meta[:engine]).to eq('context')
    expect(meta[:tool]).to eq('fts_search')
  end
end
