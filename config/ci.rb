# Local CI — the same checks GitHub Actions runs, without the round-trip.
# Run with: bin/ci   (or `ruby bin/ci` on Windows)

CI.run do
  # Steps invoke ruby/npm directly so they work on Windows too, where the
  # shell cannot exec shebang scripts.
  step "Tests: API", "ruby bin/rails test"

  step "Build: frontend (typecheck + bundle)", "npm run build --prefix frontend"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
