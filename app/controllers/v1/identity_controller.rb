module V1
  # Publish and look up long-term identity public keys, backed by the
  # tamper-evident key-transparency log. The server never sees private keys.
  class IdentityController < ApplicationController
    # GET /v1/identity — my current published keys (or 404 if none).
    def show
      identity = current_user.user_identity
      return render json: { error: "no identity published" }, status: :not_found unless identity

      render json: identity_json(identity)
    end

    # PUT /v1/identity {"kem_public_key": "...", "sig_public_key": "..."}
    # Publishes or rotates the caller's keys and appends to the log.
    def update
      kem = params.require(:kem_public_key).to_s
      sig = params.require(:sig_public_key).to_s

      identity = current_user.user_identity || current_user.build_user_identity
      identity.update!(kem_public_key: kem, sig_public_key: sig)
      KeyLogEntry.append!(api_user: current_user, kem_public_key: kem, sig_public_key: sig)

      render json: identity_json(identity)
    end

    # GET /v1/users/:name/identity — someone else's public keys, to encrypt
    # to them. Includes the fingerprint for out-of-band verification.
    def lookup
      user = ApiUser.find_by(name: params[:name])
      identity = user&.user_identity
      return render json: { error: "no identity for that user" }, status: :not_found unless identity

      render json: identity_json(identity).merge(user: user.name)
    end

    private

    def identity_json(identity)
      {
        kem_public_key: identity.kem_public_key,
        sig_public_key: identity.sig_public_key,
        fingerprint: identity.fingerprint,
        updated_at: identity.updated_at.utc.iso8601
      }
    end
  end
end
