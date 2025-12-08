class Agent < ApplicationRecord
  self.table_name = 'agents'
  belongs_to :persona, optional: true
end

