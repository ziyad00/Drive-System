# Be sure to restart your server when you modify this file.

# Allow the frontend (Vite dev server, or any origin set via CORS_ORIGINS)
# to call the API from the browser.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:5173").split(","))

    resource "/v1/*",
      headers: :any,
      methods: [ :get, :post, :put, :options, :head ]
  end
end
