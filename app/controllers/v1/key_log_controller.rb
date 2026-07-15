module V1
  # The public, append-only key-transparency log. Anyone authenticated can
  # read it and verify the hash chain independently.
  class KeyLogController < ApplicationController
    # GET /v1/keylog?since=<seq> — entries after +since+ (paged), plus the
    # server's own chain-validity check.
    def index
      since = params[:since].to_i
      entries = KeyLogEntry.where("seq > ?", since).order(:seq).limit(500).includes(:api_user)

      render json: {
        entries: entries.map { |entry| entry_json(entry) },
        head_seq: KeyLogEntry.maximum(:seq) || 0,
        chain_valid: KeyLogEntry.verify_chain
      }
    end

    private

    def entry_json(entry)
      {
        seq: entry.seq,
        user: entry.api_user.name,
        kem_public_key: entry.kem_public_key,
        sig_public_key: entry.sig_public_key,
        prev_hash: entry.prev_hash,
        entry_hash: entry.entry_hash,
        created_at: entry.created_at.utc.iso8601(6)
      }
    end
  end
end
