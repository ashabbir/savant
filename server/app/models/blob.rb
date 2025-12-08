class Blob < ApplicationRecord
  self.table_name = 'blobs'
  has_many :chunks
end

