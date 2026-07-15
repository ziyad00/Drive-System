Rails.application.routes.draw do
  namespace :v1 do
    # Blob ids are arbitrary strings and may contain slashes or dots, so the
    # id segment greedily matches everything after /v1/blobs/.
    resources :blobs, only: %i[index create show], param: :id,
                      constraints: { id: /.+/ }, format: false
    resources :backends, only: :index
    put "backends/default" => "backends#set_default"

    # File tree: path-based reads, id-based mutations.
    get "fs(/*path)" => "fs#show", format: false, defaults: { path: "" }
    get "dl/*path" => "downloads#show", format: false
    resources :folders, only: :create
    resources :files, only: :create
    put "files" => "files#update"
    resources :nodes, only: %i[update destroy] do
      member { post :copy }
      resources :versions, only: %i[index destroy] do
        member { post :restore }
      end
      resources :shares, only: %i[create destroy], controller: "shares"
      get "shares" => "shares#node_index"
    end
    get "shares" => "shares#index"
    get "identity" => "identity#show"
    put "identity" => "identity#update"
    get "users/:name/identity" => "identity#lookup"
    get "keylog" => "key_log#index"
    resources :groups, only: %i[create show] do
      post "members" => "groups#add_member"
      delete "members/:user" => "groups#remove_member", constraints: { user: /[^\/]+/ }
      post "commits" => "groups#commit"
      get "commits" => "groups#commits"
    end
    # Shared content, addressed under the grant.
    get "shared(/*path)" => "shared#show", format: false, defaults: { path: "" }
    put "shared/*path" => "shared#update", format: false
    resources :uploads, only: %i[create show destroy]
    get "trash" => "trash#index"
    delete "trash" => "trash#empty"
    post "trash/:id/restore" => "trash#restore"
    delete "trash/:id" => "trash#destroy"
    patch "uploads/:id" => "uploads#append"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
