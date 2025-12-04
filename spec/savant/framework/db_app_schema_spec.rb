#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require 'savant/framework/db'

RSpec.describe Savant::Framework::DB do
  before(:all) do
    # Prefer explicit DATABASE_URL; fall back to docker-compose default mapping
    ENV['DATABASE_URL'] ||= 'postgres://context:contextpw@localhost:5433/contextdb'
  end

  let(:db) { described_class.new }

  it 'migrates schema including app tables' do
    db.migrate_tables
    db.ensure_fts

    # basic existence checks
    expect { db.exec('SELECT 1 FROM personas LIMIT 1') }.not_to raise_error
    expect { db.exec('SELECT 1 FROM rulesets LIMIT 1') }.not_to raise_error
    expect { db.exec('SELECT 1 FROM agents LIMIT 1') }.not_to raise_error
    expect { db.exec('SELECT 1 FROM agent_runs LIMIT 1') }.not_to raise_error
    expect { db.exec('SELECT 1 FROM workflows LIMIT 1') }.not_to raise_error
    expect { db.exec('SELECT 1 FROM workflow_steps LIMIT 1') }.not_to raise_error
    expect { db.exec('SELECT 1 FROM workflow_runs LIMIT 1') }.not_to raise_error
  end

  it 'supports CRUD for personas, rulesets, agents and runs' do
    db.migrate_tables

    pid = db.create_persona('Reviewer', 'Be concise and strict')
    expect(pid).to be_a(Integer)
    expect(db.get_persona_by_name('Reviewer')).not_to be_nil

    rid = db.create_ruleset('Default', '- No PII\n- Keep logs short')
    expect(rid).to be_a(Integer)
    expect(db.get_ruleset_by_name('Default')).not_to be_nil

    aid = db.create_agent(
      name: 'Code Reviewer',
      persona_id: pid,
      driver_prompt: 'Review patch and comment',
      rule_set_ids: [rid],
      favorite: true
    )
    expect(aid).to be_a(Integer)

    agent = db.get_agent(aid)
    expect(agent['name']).to eq('Code Reviewer')

    # record a run
    run_id = db.record_agent_run(
      agent_id: aid,
      input: 'Please review',
      output_summary: 'Looks good',
      status: 'ok',
      duration_ms: 1200,
      full_transcript: { steps: [{ msg: 'hi' }] }
    )
    expect(run_id).to be_a(Integer)
    runs = db.list_agent_runs(aid, limit: 5)
    expect(runs.length).to eq(1)
  end

  it 'supports workflows, steps, and runs' do
    db.migrate_tables

    wid = db.create_workflow(
      name: 'Triager',
      description: 'Routes tickets',
      graph: { nodes: [{ id: 'a' }], edges: [] },
      favorite: false
    )
    expect(wid).to be_a(Integer)

    sid = db.add_workflow_step(
      workflow_id: wid,
      name: 'Decide',
      step_type: 'decision',
      config: { rule: 'severity>2' },
      position: 1
    )
    expect(sid).to be_a(Integer)

    steps = db.list_workflow_steps(wid)
    expect(steps.length).to eq(1)
    expect(steps.first['name']).to eq('Decide')

    run_id = db.record_workflow_run(
      workflow_id: wid,
      input: 'Ticket 123',
      output: 'Escalate',
      status: 'ok',
      duration_ms: 250,
      transcript: { events: [{ type: 'route', to: 'L2' }] }
    )
    expect(run_id).to be_a(Integer)
    wruns = db.list_workflow_runs(wid, limit: 5)
    expect(wruns.length).to eq(1)
  end
end

