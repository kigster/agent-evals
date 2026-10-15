# frozen_string_literal: true

# A writable copy of the toy suite in a temp directory, for specs that break
# a file on purpose. Real files, no filesystem mocks.
module TmpSuite
  # @return [String] the copy's evals/ directory
  def copy_toy_suite
    dir = Dir.mktmpdir("agent-evals")
    FileUtils.cp_r(File.join(TOY_SUITE, "evals"), dir)
    File.join(dir, "evals")
  end

  # @return [Agent::Evals::Configuration] the toy suite's pieces over another root
  def configuration_for(root, cases: Agent::Evals::Configuration::DEFAULT_GLOB)
    Agent::Evals::Configuration.new.tap do |c|
      c.suite "copy", root: root
      c.cases cases
      c.adapter Agent::Evals.configuration.adapter
      c.scorer Agent::Evals.configuration.scorer
    end
  end
end

RSpec.configure { it.include TmpSuite }
