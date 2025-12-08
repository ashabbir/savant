class Chunk < ApplicationRecord
  self.table_name = 'chunks'
  belongs_to :blob
end

