# Metadata record for every stored blob. The actual bytes live in the
# configured storage backend; this table only tracks what was stored where.
#
# Blobs belong to the API user who stored them, and all reads are scoped to
# the owner. Rows created before multi-tenancy have no owner (NULL).
class Blob < ApplicationRecord
  belongs_to :api_user, optional: true

  validates :blob_id, presence: true, uniqueness: { scope: :api_user_id }
  validates :size, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :backend, presence: true

  # The identifier handed to storage adapters. Namespacing by owner keeps
  # different users' blobs with the same id at different storage keys
  # (adapters hash this value — see Storage::Base#key_for). Legacy ownerless
  # rows keep their original un-namespaced key so they stay retrievable.
  def storage_id
    api_user_id ? "#{api_user_id}/#{blob_id}" : blob_id
  end
end
