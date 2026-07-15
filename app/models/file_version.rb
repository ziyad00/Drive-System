# A prior content of a file node. Owns the blob that was current before a
# replacement; rows are removed either by restore (blob promoted back to
# current) or by pruning/deletion (blob purged).
class FileVersion < ApplicationRecord
  belongs_to :node
  belongs_to :blob
end
