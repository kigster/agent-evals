# frozen_string_literal: true

RSpec.describe Agent::Evals do
  it "is configured by the toy suite" do
    expect(described_class).to be_configured
    expect(described_class.configuration.name).to eq("toy")
  end

  describe ".configure" do
    it "yields the one configuration" do
      yielded = nil
      described_class.configure { yielded = it }
      expect(yielded).to be(described_class.configuration)
    end
  end

  describe ".reset!" do
    # Put the toy suite back after, since every other spec relies on it.
    after { load TOY_HELPER }

    it "forgets the suite" do
      described_class.reset!
      expect(described_class).not_to be_configured
    end
  end

  describe ".optional!" do
    it "requires a gem that is present" do
      expect { described_class.optional!("json", needed_for: "parsing") }.not_to raise_error
    end

    it "names the gem that is missing and what needed it" do
      expect { described_class.optional!("no_such_gem_here", needed_for: "the thing") }
        .to raise_error(Agent::Evals::MissingDependency, /the thing needs the no_such_gem_here gem: add `gem "no_such_gem_here"`/)
    end
  end
end
