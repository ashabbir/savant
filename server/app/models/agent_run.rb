class AgentRun < ApplicationRecord
  self.table_name = 'agent_runs'
  belongs_to :agent, optional: true
end

