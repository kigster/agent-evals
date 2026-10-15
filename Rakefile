# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"

RSpec::Core::RakeTask.new(:spec)

YARD::Rake::YardocTask.new(:doc) do |t|
  t.files = %w[lib/**/*.rb exe/* - README.md LICENSE.txt CHANGELOG.md]
end

task default: :spec
