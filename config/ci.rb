# Local CI — the same checks GitHub Actions runs, without the round-trip.
# Run with: bin/ci   (or `ruby bin/ci` on Windows)

# gitleaks and osv-scanner are standalone binaries (winget/brew/apt install
# gitleaks, osv-scanner); their steps are skipped when not installed, and
# GitHub Actions always runs them regardless.
def scanner_available?(probe)
  system(probe, out: File::NULL, err: File::NULL)
end

CI.run do
  # Steps invoke ruby/npm directly so they work on Windows too, where the
  # shell cannot exec shebang scripts.
  step "Tests: API", "ruby bin/rails test"

  step "Security: Brakeman (Rails static analysis)",
       "bundle exec brakeman --exit-on-warn --no-pager --quiet"

  if scanner_available?("gitleaks version")
    step "Security: gitleaks (secrets in git history)", "gitleaks git --no-banner --redact"
  end

  if scanner_available?("osv-scanner --version")
    step "Security: OSV-Scanner (known dependency vulns)",
         "osv-scanner scan source -L Gemfile.lock -L frontend/package-lock.json"
  end

  step "Build: frontend (typecheck + bundle)", "npm run build --prefix frontend"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
