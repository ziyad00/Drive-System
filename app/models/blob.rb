# Metadata record for every stored blob. The actual bytes live in the
# configured storage backend; this table only tracks what was stored where.
class Blob < ApplicationRecord
  validates :blob_id, presence: true, uniqueness: true
  validates :size, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :backend, presence: true
end
