# In development, seed a well-known API user so the API and frontend work
# out of the box with the token "dev-token". Production tokens are minted
# with `bin/rails simple_drive:create_user[name]`.
if Rails.env.development?
  ApiUser.find_or_create_by!(token_digest: ApiUser.digest("dev-token")) do |user|
    user.name = "dev"
  end
end
