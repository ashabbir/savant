# frozen_string_literal: true

require 'yaml'
require_relative '../../lib/savant/engines/workflow/context'
require_relative '../../lib/savant/engines/workflow/interpolator'

RSpec.describe Savant::Workflow::Interpolator do
  it 'interpolates strings, arrays, and objects with params and prior steps' do
    ctx = Savant::Workflow::Context.new(params: { 'ticket' => 'ABC-123', 'n' => 2 })
    ctx.set('diff', { 'files' => ['a.rb', 'b.rb'] })
    intr = described_class.new(ctx)

    obj = {
      'text' => 'Ticket {{ params.ticket }} changed {{ diff.files }}',
      'arr' => ['X', '{{ params.n }}', { 'k' => '{{ diff.files.0 }}' }]
    }
    out = intr.apply(obj)
    expect(out['text']).to include('ABC-123')
    expect(out['text']).to include('["a.rb","b.rb"]')
    expect(out['arr'][1]).to eq('2')
    expect(out['arr'][2]['k']).to eq('a.rb')
  end
end
