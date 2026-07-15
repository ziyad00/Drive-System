# A node in a user's file tree: a folder or a file. Files point at a Blob
# for their content; folders exist purely in metadata.
#
# The tree is an adjacency list (parent_id), so moving a subtree of any
# size is a single column update — inherently atomic — and renames never
# touch storage: bytes are addressed by the blob's immutable id, not by
# path. Each user has one root sentinel (parent: nil, name: ""); every
# real node hangs off it.
class Node < ApplicationRecord
  KINDS = %w[folder file].freeze

  belongs_to :api_user
  belongs_to :parent, class_name: "Node", optional: true
  belongs_to :blob, optional: true
  has_many :children, class_name: "Node", foreign_key: :parent_id,
                      inverse_of: :parent, dependent: :destroy
  has_many :file_versions, dependent: :destroy
  has_many :shares, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, unless: :root?
  validates :name, uniqueness: { scope: [ :api_user_id, :parent_id ] }, unless: :root?
  validate :name_contains_no_separators
  validate :parent_is_a_folder
  validate :files_have_content, if: :file?

  # prepend: association dependent-destroy callbacks fire first otherwise,
  # deleting the version rows before their blobs can be purged.
  before_destroy :purge_version_blobs, prepend: true
  after_destroy :purge_blob

  def root?
    parent_id.nil?
  end

  def sentinel?
    role.present?
  end

  def trashed?
    trashed_at.present?
  end

  def folder?
    kind == "folder"
  end

  def file?
    kind == "file"
  end

  def path
    return "/" if root?

    prefix = parent.root? ? "" : parent.path
    "#{prefix}/#{name}"
  end

  # Self and every ancestor up to (not including) the root sentinel.
  def self_and_ancestors
    chain = []
    node = self
    while node && !node.root?
      chain << node
      node = node.parent
    end
    chain
  end

  def descendant_of?(other)
    node = parent
    while node
      return true if node == other

      node = node.parent
    end
    false
  end

  private

  def name_contains_no_separators
    errors.add(:name, "cannot contain /") if name&.include?("/")
    errors.add(:name, "is reserved") if [ ".", ".." ].include?(name)
  end

  def parent_is_a_folder
    errors.add(:parent, "must be a folder") if parent && !parent.folder?
  end

  def files_have_content
    errors.add(:blob, "is required for files") unless blob
  end

  # Deleting a file node removes its bytes from the storage backend and its
  # metadata row. Missing backend content is fine — delete is idempotent.
  def purge_blob
    BlobWriter.purge!(blob) if blob
  end

  # Each version row goes first (it holds a foreign key to its blob),
  # then the blob's bytes and metadata.
  def purge_version_blobs
    file_versions.includes(:blob).each do |version|
      blob = version.blob
      version.destroy!
      BlobWriter.purge!(blob)
    end
  end
end
