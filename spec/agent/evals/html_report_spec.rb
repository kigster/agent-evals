# frozen_string_literal: true

RSpec.describe Agent::Evals::HtmlReport do
  describe "the report template" do
    let(:template_paths) do
      %w[
        lib/agent/evals/templates/html_report.html.erb
        lib/agent/evals/templates/html_report.css
        lib/agent/evals/templates/html_report.js
      ]
    end
    let(:gem_specification) { Gem::Specification.load(File.expand_path("../../../agent-evals.gemspec", __dir__)) }

    it "includes the template and assets in the built gem" do
      expect(gem_specification.files).to include(*template_paths)
    end
  end
end
