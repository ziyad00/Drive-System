# An API consumer. Requests authenticate with a Bearer token; only the
# SHA-256 digest of the token is stored. Each user may set a personal
# default storage backend, falling back to the system default otherwise.
class ApiUser < ApplicationRecord
  has_many :blobs, dependent: :restrict_with_exception
  has_many :nodes, dependent: :restrict_with_exception
  has_many :uploads, dependent: :destroy

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :default_backend, inclusion: { in: Storage::ADAPTERS.keys }, allow_nil: true

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def self.authenticate(token)
    find_by(token_digest: digest(token))
  end

  # Creates a user and returns [user, plaintext_token]. The token is only
  # available at creation time; afterwards only its digest exists.
  def self.generate!(name:)
    token = SecureRandom.base58(32)
    user = create!(name: name, token_digest: digest(token))
    [ user, token ]
  end

  def effective_backend
    default_backend.presence || Storage.default_backend
  end

  # The sentinel at the top of this user's file tree.
  def root_node
    nodes.find_or_create_by!(parent_id: nil) do |node|
      node.kind = "folder"
      node.name = ""
    end
  end
end
