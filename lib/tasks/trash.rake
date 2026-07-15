namespace :simple_drive do
  desc "Permanently purge trash entries older than TRASH_RETENTION_DAYS (default 30)"
  task purge_trash: :environment do
    puts "Purged #{Trash.purge_expired!} expired trash entr(ies)."
  end
end
