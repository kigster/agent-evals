# frozen_string_literal: true

RSpec.describe Agent::Evals::SchemaValidator do
  subject(:validator) do
    described_class.new(
      "status"  => { type: :enum, enum: %w[single married] },
      "kids"    => { type: "integer", nullable: true },
      "rate"    => { type: :number },
      "name"    => { type: :string },
      "remote"  => { type: :boolean },
      "add_ons" => { type: :multi_enum, values: %w[drone album] }
    )
  end

  let(:good) { { "status" => "single", "kids" => nil, "rate" => 1.5, "name" => "Alan", "remote" => true, "add_ons" => ["drone"] } }

  it { expect(validator.names).to eq(%w[status kids rate name remote add_ons]) }
  it { expect(validator).to be_valid(good) }
  it { expect(validator).to be_valid(good.transform_keys(&:to_sym)) }
  it { expect(validator.problems("nope")).to eq(['"nope" is not a Hash']) }

  it "reports every problem" do
    bad = { "status" => "widowed", "kids" => "2", "rate" => "x", "name" => 1, "remote" => "yes", "add_ons" => %w[drone yacht], "bogus" => 1 }
    expect(validator.problems(bad)).to contain_exactly(
      "unknown fields bogus",
      'status: "widowed" is not one of single|married',
      'kids: "2" is not an integer',
      'rate: "x" is not a number',
      "name: 1 is not a string",
      'remote: "yes" is not a boolean',
      "add_ons: yacht not in drone|album"
    )
  end

  it { expect(validator.problems(good.except("name"))).to eq(["missing name"]) }
  it { expect(validator.problems(good.merge("name" => nil))).to eq(["name: is null"]) }
  it { expect(validator.problems(good.merge("add_ons" => "drone"))).to eq(['add_ons: "drone" is not an array']) }
  it { expect { described_class.new("x" => { type: :date }) }.to raise_error(ArgumentError, /unknown type :date/) }
end
