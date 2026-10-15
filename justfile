set shell := ["bash", "-c"]

version := `grep VERSION lib/agent/evals/version.rb | awk '{print $3}' | tr -d '"' | tr -d '\n'`
# `rbenv init - bash` prints the shell code meant to be eval'd; without the
# `-` it prints human instructions that eval then tries to run.
rbenv    := 'eval "$(rbenv init - bash 2>/dev/null || true)"; bundle exec '
repo     := 'git@github.com:kigster/agent-evals.git'
gem_name := 'agent-evals'
gem_file := 'pkg/' + gem_name + '-' + version + '.gem'

[no-exit-message]
recipes:
    just --choose

# Install the bundle
install:
    bundle install

# Lint with RuboCop
lint:
    {{ rbenv }} rubocop

# Lint and autocorrect; pass -A for unsafe corrections
format *args:
    {{ rbenv }} rubocop -a {{ args }}

# Run the specs (no network)
test *args:
    {{ rbenv }} rspec {{ args }}

# Run the toy suite's offline commands through the executable
toy:
    cd spec/fixtures/toy_suite && ../../../exe/agent-evals cases && ../../../exe/agent-evals verify

# What CI runs: lint, specs, toy suite; no network
ci: lint test toy

# Run every lefthook pre-commit hook
lefthook:
    {{ rbenv }} lefthook run pre-commit --all-files

# Print the gem version
version:
    @echo "{{ version }}"

# Generate YARD documentation
doc:
    {{ rbenv }} yard doc

# Build the gem into pkg/
build:
    mkdir -p pkg
    gem build {{ gem_name }}.gemspec --output "{{ gem_file }}"

# Tag v{{ version }} and publish the GitHub release
release:
    git fetch --tags
    git tag -f "v{{ version }}"
    git push -f --tags
    gh release delete -y "v{{ version }}" --repo {{ repo }} 2>/dev/null || true
    gh release create "v{{ version }}" --generate-notes --repo {{ repo }}
