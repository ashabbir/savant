class Workflow < ApplicationRecord
  self.table_name = 'workflows'
  has_many :workflow_steps
  has_many :workflow_runs
end

