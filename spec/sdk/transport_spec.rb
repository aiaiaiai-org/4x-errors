# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

RSpec.describe Aiaiaiai::Errors::Transport do
  subject(:transport) { described_class.new(configuration) }

  let(:configuration) do
    Aiaiaiai::Errors::Configuration.new.tap do |config|
      config.token = "token"
      config.project = "nilx-one/web"
      config.proxy = nil
      config.open_timeout = 0.5
      config.read_timeout = 0.3
      config.write_timeout = 0.5
      config.endpoint = endpoint
    end
  end

  let(:document) do
    Aiaiaiai::Errors::Payload.request(
      project: "nilx-one/web",
      events: [{"error_id" => "a.one", "environment" => "test"}]
    )
  end

  # Every one of these is a way the network fails in production, and every one
  # of them must end as an outcome rather than an exception.
  describe "network failures" do
    context "when the host does not resolve" do
      let(:endpoint) { "https://collector.invalid" }

      it "is a transient failure" do
        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
      end
    end

    context "when the connection is refused" do
      let(:endpoint) { "http://127.0.0.1:1" }

      it "is a transient failure" do
        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
      end
    end

    context "when the collector accepts the connection and says nothing" do
      let(:stub) { StubCollector.new(mode: :silent) }
      let(:endpoint) { stub.endpoint }

      after { stub.stop }

      it "gives up on the read timeout" do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
      end
    end

    context "when TLS cannot be established" do
      let(:stub) { StubCollector.new(mode: :accepted) }
      let(:endpoint) { stub.endpoint(scheme: "https") }

      after { stub.stop }

      it "is a transient failure" do
        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
      end
    end

    context "when the answer is not HTTP at all" do
      let(:stub) { StubCollector.new(mode: :garbage) }
      let(:endpoint) { stub.endpoint }

      after { stub.stop }

      it "is a transient failure rather than an exception" do
        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
      end
    end
  end

  describe "collector answers" do
    let(:stub) { StubCollector.new(mode: mode) }
    let(:endpoint) { stub.endpoint }

    after { stub.stop }

    context "when the event is accepted" do
      let(:mode) { :accepted }

      it "is delivered" do
        expect(transport.deliver(document)).to eq(described_class::DELIVERED)
      end

      it "sends the token as a bearer credential and nothing else" do
        transport.deliver(document)
        request = stub.received.first

        expect(request[:headers]).to match(/^authorization: Bearer token\r$/i)
        expect(request[:headers]).to include("#{Aiaiaiai::Errors::SDK_NAME}/#{Aiaiaiai::Errors::VERSION}")
        expect(JSON.parse(request[:body])["protocol_version"]).to eq("errors.v1")
      end
    end

    context "when the token is rejected" do
      let(:mode) { :unauthorized }

      it "is a permanent failure: sending it again cannot help" do
        expect(transport.deliver(document)).to eq(described_class::PERMANENT_FAILURE)
      end
    end

    context "when the project does not match the token" do
      let(:mode) { :forbidden }

      it "is a permanent failure" do
        expect(transport.deliver(document)).to eq(described_class::PERMANENT_FAILURE)
      end
    end

    context "when the collector fails" do
      let(:mode) { :server_error }

      it "is a transient failure" do
        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
      end
    end

    context "when the collector asks for less traffic" do
      let(:mode) { :too_many_requests }

      it "is a transient failure" do
        expect(transport.deliver(document)).to eq(described_class::TRANSIENT_FAILURE)
      end
    end
  end

  describe "a payload that cannot be serialised" do
    let(:endpoint) { "http://127.0.0.1:1" }

    it "is a permanent failure, not an exception" do
      unserialisable = {"events" => [{"binary" => "\xff\xfe".b}]}

      expect(transport.deliver(unserialisable)).to eq(described_class::PERMANENT_FAILURE)
    end
  end

  describe "a nonsensical endpoint" do
    let(:endpoint) { "not a url at all" }

    it "is a permanent failure, decided without touching the network" do
      expect(transport.deliver(document)).to eq(described_class::PERMANENT_FAILURE)
    end
  end
end
