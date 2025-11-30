# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'savant CLI' do
  it 'lists tools for the context service' do
    cmd = %(ruby bin/savant list tools --service=context)
    out = `#{cmd}`
    expect($CHILD_STATUS.success?).to be(true)
    expect(out).to include('fts_search')
  end
end
