class CreateApiUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :api_users do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :default_backend

      t.timestamps
    end

    add_index :api_users, :token_digest, unique: true
  end
end
