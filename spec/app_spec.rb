# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

# frozen_string_literal: true

require "rack/test"
require "rspec"
require_relative "../app"

RSpec.describe Aiaiaiai::Errors::App do
  include Rack::Test::Methods

  def app
    described_class.app
  end

  it "exposes a health endpoint" do
    get "/health"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq("status" => "ok")
  end

  it "identifies the service at the root" do
    get "/"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include(
      "service" => "4x-errors",
      "status" => "ok"
    )
  end
end
