set shell := ["bash", "-c"]

version := `grep VERSION lib/agent/evals/version.rb | awk '{print $3}' | tr -d '"' | tr -d '\n'`
# The `-` matters: `rbenv init bash` prints human instructions ("skipping
# ~/.bash_login: already configured"), which eval then tries to run, and the
# recipe dies with "skipping: command not found". `rbenv init - bash` prints
# the shell code that is meant to be eval'd.
rbenv   := 'eval "$(rbenv init - bash 2>/dev/null || true)"; bundle exec '
repo    := 'git@github.com:kigster/agent-evals.git'

# 1Password secret reference for the RubyGems TOTP, and the full path to `op`
# because a recipe does not inherit an interactive shell's PATH.
# The account is NOT named here: it is a private 1Password address and this
# file is public. `op` reads it from OP_ACCOUNT, exported by the ecosystem
# root's .envrc, which lives outside every repo. Two accounts are
# registered and only one holds the open-source-repos vault, so without
# OP_ACCOUNT the read can resolve against the wrong one, return nothing,
# and publish silently falls back to prompting mid-release.
op       := '/opt/homebrew/bin/op'
otp_ref  := 'op://open-source-repos/ruby-gems/one-time password?attribute=otp'

gem_name := 'agent-evals'
gem_file := 'pkg/' + gem_name + '-' + version + '.gem'
gem_url  := 'https://rubygems.org/gems/' + gem_name

# The executable, as seen from inside either example suite's folder.
exe      := '../../../exe/agent-evals'

[no-exit-message]
recipes:
    just --choose

# Install the bundle
install:
    bundle install

# Lint with RuboCop
lint:
    {{ rbenv }} rubocop

# Lint and autocorrect (pass -A for unsafe corrections), then format Markdown
format *args:
    {{ rbenv }} rubocop -a {{ args }}
    fd -e md -X mdformat --wrap no

# Run the specs (no network)
test *args:
    {{ rbenv }} rspec {{ args }}

# Example 1, the eval_helper.rb suite: cases, verify, compare; or pass a command
[working-directory: 'spec/fixtures/toy_suite']
toy *args:
    #!/usr/bin/env bash
    set -euo pipefail
    echo -e "\033[7;35m\n\n❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯ TOY SUITE ——————————————————————————————————————\n\n\033[0m"
    sleep 1
    eval "$(rbenv init - bash 2>/dev/null || true)"
    if [[ -n "{{ args }}" ]]; then
      bundle exec {{ exe }} {{ args }}
    else
      bundle exec {{ exe }} cases
      bundle exec {{ exe }} verify
      bundle exec {{ exe }} compare --local --no-open
    fi

# Example 2, the config-only suite: cases, verify, compare; or pass a command
[working-directory: 'spec/fixtures/config_only_suite']
config-only *args:
    #!/usr/bin/env bash
    set -euo pipefail
    echo -e "\033[7;35m\n\n❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯❯ CONFIG ONLY SUITE ——————————————————————————————————————\n\n\033[0m"
    sleep 1
    eval "$(rbenv init - bash 2>/dev/null || true)"
    # Its require: toy_suite/evals lives in the toy suite's lib/, not in a gem.
    export RUBYLIB="../toy_suite/lib${RUBYLIB:+:$RUBYLIB}"
    if [[ -n "{{ args }}" ]]; then
      bundle exec {{ exe }} {{ args }}
    else
      bundle exec {{ exe }} cases
      bundle exec {{ exe }} verify
      bundle exec {{ exe }} compare --local --no-open
    fi

# Run both example suites end to end (no network)
examples: toy config-only

# What CI runs: lint, specs, both example suites; no network
ci: lint test examples

alias check-all := ci

# Remove .DS_Store files and tmp/
clean:
    find . -name .DS_Store -not -path './.git/*' -delete -print
    rm -rf tmp/*

# Run every lefthook pre-commit hook
lefthook:
    {{ rbenv }} lefthook run pre-commit --all-files

# Print the gem version
version:
    @echo "{{ version }}"

# Remove pkg/ and other build products
clobber:
    {{ rbenv }} rake clobber

# Generate YARD documentation
doc:
    {{ rbenv }} rake doc

# Build the gem into pkg/
build:
    mkdir -p pkg
    gem build {{ gem_name }}.gemspec --output "{{ gem_file }}"

# `gem push` rather than `rake release`: release also guards the tree, tags and
# pushes git — which `just release` does deliberately and separately — and it
# gives no way to pass a 2FA code, so it always stopped to prompt.
#
# The code comes from 1Password unless one is passed in:
#
#   just publish            # read the code from 1Password
#   just publish 123456     # use this code
#
# Build the .gem and push it to RubyGems, non-interactively
publish otp="": build
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(rbenv init - bash 2>/dev/null || true)"

    # `|| true` is load-bearing: under `set -e` a failed `op read` — not signed
    # in to 1Password, item renamed, op not installed — would abort the recipe
    # before the prompting fallback below could run.
    otp="{{ otp }}"
    [[ -n "${otp}" ]] || otp=$({{ op }} read "{{ otp_ref }}" 2>/dev/null || true)

    if [[ -n "${otp}" ]]; then
      gem push "{{ gem_file }}" --otp "${otp}"
    else
      echo "rubygems: no OTP available — gem push will prompt if 2FA is required."
      gem push "{{ gem_file }}"
    fi

    # Only reachable when the push succeeded: `set -e` aborts the recipe on a
    # non-zero `gem push`, so the page never opens for a release that failed.
    echo "published {{ gem_name }} {{ version }} → {{ gem_url }}"
    open "{{ gem_url }}" 2>/dev/null || xdg-open "{{ gem_url }}" 2>/dev/null || true

# Tag the current version and publish the GitHub release
release:
    git fetch --tags
    git tag -f "v{{ version }}"
    git push -f --tags
    gh release delete -y "v{{ version }}" --repo {{ repo }} 2>/dev/null || true
    gh release create "v{{ version }}" --generate-notes --repo {{ repo }}
