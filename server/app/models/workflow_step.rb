class WorkflowStep < ApplicationRecord
  self.table_name = 'workflow_steps'
  belongs_to :workflow
end

