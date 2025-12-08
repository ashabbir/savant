class WorkflowRun < ApplicationRecord
  self.table_name = 'workflow_runs'
  belongs_to :workflow
end

