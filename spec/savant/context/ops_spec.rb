# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/framework/db'
require_relative '../../../lib/savant/engines/context/ops'

RSpec.describe Savant::Context::Ops do
  describe '#repos_readme_list' do
    it 'returns truncated README snippets and forwards filter' do
      db = instance_double(Savant::DB)
      allow(db).to receive(:list_repos_with_readme).and_return([
                                                                 { name: 'repo-a', readme_text: 'Hello World' },
                                                                 { name: 'repo-b', readme_text: nil }
                                                               ])
      ops = described_class.new(db: db)

      result = ops.repos_readme_list(filter: 'repo', max_length: 5)

      expect(db).to have_received(:list_repos_with_readme).with(filter: 'repo')
      expect(result).to eq([
                             { name: 'repo-a', readme: 'Hello', truncated: true },
                             { name: 'repo-b', readme: nil, truncated: false }
                           ])
    end
  end
end
