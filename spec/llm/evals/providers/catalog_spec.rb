# frozen_string_literal: true

RSpec.describe LLM::Evals::Providers::Catalog do
  it "turns a failed request into an Error" do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError, "offline")
    expect { described_class.fetch("https://example.com/models") }
      .to raise_error(LLM::Evals::Error, %r{could not list models at https://example.com/models: offline})
  end

  it "turns a non-2xx into an Error" do
    allow(Net::HTTP).to receive(:start).and_return(Net::HTTPUnauthorized.new("1.1", "401", "no"))
    expect { described_class.fetch("https://example.com/models") }.to raise_error(LLM::Evals::Error, /HTTP 401/)
  end

  it "parses the list" do
    ok = Net::HTTPOK.new("1.1", "200", "ok")
    allow(ok).to receive(:body).and_return('{"data":[]}')
    allow(Net::HTTP).to receive(:start).and_return(ok)
    expect(described_class.fetch("https://example.com/models", "Authorization" => "Bearer k")).to eq("data" => [])
  end
end
