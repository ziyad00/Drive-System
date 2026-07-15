namespace :simple_drive do
  desc "Remove resumable-upload sessions idle for more than 48 hours"
  task purge_stale_uploads: :environment do
    count = 0
    Upload.stale.find_each do |upload|
      upload.destroy!
      count += 1
    end
    puts "Purged #{count} stale upload(s)."
  end
end
