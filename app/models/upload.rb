# A resumable upload session. Bytes accumulate in a staging file on local
# disk (regardless of the final storage backend) until offset reaches
# expected_size; finalization then runs the normal file write path.
class Upload < ApplicationRecord
  belongs_to :api_user

  validates :path, presence: true
  validates :expected_size, numericality: { greater_than: 0 }
  validates :offset, numericality: { greater_than_or_equal_to: 0 }

  after_destroy :remove_staging

  def complete?
    offset >= expected_size
  end

  def staging_path
    File.join(self.class.staging_root, id.to_s)
  end

  def append_chunk!(bytes)
    FileUtils.mkdir_p(self.class.staging_root)
    # The first chunk truncates: a stale staging file (crashed process,
    # recycled id) must never leak into a fresh session.
    File.open(staging_path, offset.zero? ? "wb" : "ab") { |file| file.write(bytes) }
    update!(offset: offset + bytes.bytesize)
  end

  def staged_bytes
    File.binread(staging_path)
  end

  def self.staging_root
    Rails.root.join("tmp", "uploads").to_s
  end

  # Abandoned sessions eligible for cleanup (simple_drive:purge_stale_uploads).
  scope :stale, -> { where(updated_at: ..48.hours.ago) }

  private

  def remove_staging
    File.delete(staging_path) if File.exist?(staging_path)
  end
end
