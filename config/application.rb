require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SimpleDrive
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Cap request bodies before parsing. The ceiling is the configured max
    # decoded blob size, grown by the Base64 4/3 factor plus JSON envelope
    # headroom, so any request that could exceed MAX_BLOB_BYTES is rejected
    # with 413 at the middleware layer.
    require_relative "../lib/middleware/request_size_limiter"
    max_blob_bytes = Integer(ENV.fetch("MAX_BLOB_BYTES", 26_214_400))
    config.middleware.insert_before ActionDispatch::ShowExceptions, RequestSizeLimiter,
                                    max_bytes: (max_blob_bytes * 4 / 3.0).ceil + 8_192

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end
end
