namespace :simple_drive do
  desc "Create an API user and print its Bearer token (shown only once)"
  task :create_user, [ :name ] => :environment do |_task, args|
    name = args[:name].presence or abort "usage: bin/rails simple_drive:create_user[name]"

    user, token = ApiUser.generate!(name: name)
    puts "Created API user ##{user.id} (#{user.name})"
    puts "Token: #{token}"
    puts "Store it now — only its digest is kept in the database."
  end
end
