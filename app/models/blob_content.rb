# Row-per-blob storage used by the database backend. Kept separate from the
# Blob metadata table on purpose: metadata tracking and storage are different
# concerns, and the storage backend must be swappable without touching metadata.
class BlobContent < ApplicationRecord
  validates :blob_id, presence: true, uniqueness: true
end
