namespace :encryption do
  desc "Re-wrap all encrypted data keys under the KMS master key's latest version (zero data movement)"
  task rewrap: :environment do
    scope = Blob.where(encryption: "sse").where.not(wrapped_dek: nil)
    total = scope.count
    puts "Rewrapping #{total} data key(s) under the latest KEK version..."
    scope.find_each.with_index do |blob, i|
      blob.update_column(:wrapped_dek, Kms.rewrap(blob.wrapped_dek))
      puts "  #{i + 1}/#{total}" if ((i + 1) % 100).zero?
    end
    puts "Done. Stored ciphertext was never touched."
  end
end
