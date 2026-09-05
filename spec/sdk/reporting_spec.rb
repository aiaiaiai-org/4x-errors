# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# The central invariant, stated as tests: reporting a failure must never become
# one. Every example here puts the SDK in a situation that would break a naive
# reporter and then asserts that the host is unaffected.
RSpec.describe Aiaiaiai::Errors do
  def configure(endpoint: "http://127.0.0.1:1", **overrides)
    described_class.configure do |config|
      config.endpoint = endpoint
      config.token = "token"
      config.project = "nilx-one/web"
      config.environment = "test"
      config.proxy = nil
      config.max_retries = 0
      config.flush_interval = 0.05
      config.open_timeout = 0.3
      config.read_timeout = 0.3
      config.shutdown_timeout = 1.0
      overrides.each { |name, value| config.public_send(:"#{name}=", value) }
    end
  end

  describe "without configuration" do
    it "reports through a null reporter" do
      expect(described_class.configured?).to be(false)
      expect(described_class.reporter).to be_a(Aiaiaiai::Errors::NullReporter)
    end

    it "accepts every call and does nothing" do
      expect(described_class.capture(RuntimeError.new("x"), error_id: "a.one")).to be(false)
      expect(described_class.report(error_id: "a.one")).to be(false)
      expect(described_class.relate(source: "a.one", type: "root_cause_of", target: "b.two",
        confidence: 1.0, evidence: %w[human_review])).to be(false)
      expect(described_class.flush).to be(true)
    end

    it "starts no threads" do
      before = Thread.list.length
      10.times { described_class.report(error_id: "a.one") }

      expect(Thread.list.length).to eq(before)
    end

    it "stays a null reporter when the configuration is incomplete" do
      described_class.configure { |config| config.endpoint = "https://errors.example" }

      expect(described_class.configured?).to be(false)
    end
  end

  describe "when the collector cannot be reached" do
    it "does not raise, and does not delay the caller" do
      configure(endpoint: "http://127.0.0.1:1")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      100.times { |index| described_class.report(error_id: "a.one", message: "m#{index}") }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 1.0
      expect(described_class.flush(timeout: 2.0)).to be(true)
    end

    it "survives a host that does not resolve" do
      configure(endpoint: "https://collector.invalid")

      expect { described_class.report(error_id: "a.one") }.not_to raise_error
      described_class.flush(timeout: 2.0)
    end
  end

  describe "when the payload is hostile" do
    before { configure }

    it "survives a context that cannot be serialised" do
      hostile = Class.new { def to_s = raise("nope") }.new

      expect { described_class.report(error_id: "a.one", context: {"bad" => hostile}) }.not_to raise_error
    end

    it "survives a context far above the protocol limit" do
      expect { described_class.report(error_id: "a.one", context: {"blob" => "x" * 5_000_000}) }.not_to raise_error
    end

    it "survives an error id that is not a semantic identifier, and sends nothing" do
      expect(described_class.report(error_id: "Something Went Wrong")).to be_nil
      expect(described_class.statistics[:queued]).to be_zero
    end

    it "survives a relation with no usable evidence" do
      expect(described_class.relate(source: "a.one", type: "root_cause_of", target: "b.two",
        confidence: 1.0, evidence: [])).to be_nil
    end

    it "survives an exception with no backtrace and a broken message" do
      broken = Class.new(StandardError) { def message = raise("nope") }.new

      expect { described_class.capture(broken, error_id: "a.one") }.not_to raise_error
    end
  end

  describe "when the queue is full" do
    it "drops the newest report and counts it, rather than growing" do
      configure(queue_limit: 5, flush_interval: 30)

      50.times { described_class.report(error_id: "a.one") }

      expect(described_class.statistics[:queued]).to be <= 5
      expect(described_class.statistics[:dropped]).to be_positive
    end
  end

  describe "when reporting fails inside the reporter" do
    it "does not report about itself" do
      configure
      reported = 0
      described_class.configuration.on_internal_error = lambda do |_error|
        reported += 1
        described_class.report(error_id: "reporter.failed")
      end

      described_class.report(error_id: "Not Valid")

      expect(reported).to eq(1)
      expect(described_class.statistics[:queued]).to be_zero
    end

    it "ignores a report raised from inside the delivery thread" do
      configure
      Thread.new do
        Aiaiaiai::Errors::RecursionGuard.claim_thread
        described_class.report(error_id: "a.one")
      end.join

      expect(described_class.statistics[:queued]).to be_zero
    end
  end

  describe "delivery" do
    let(:stub) { StubCollector.new(mode: :accepted) }

    after { stub.stop }

    it "sends what was reported, in one request per batch" do
      configure(endpoint: stub.endpoint, batch_size: 10)

      3.times { |index| described_class.report(error_id: "a.one", message: "m#{index}", tags: {"i" => index.to_s}) }
      described_class.flush(timeout: 2.0)

      documents = stub.received.map { |request| JSON.parse(request[:body]) }
      expect(documents.sum { |document| document["events"].length }).to eq(3)
      expect(documents.first["project"]).to eq("nilx-one/web")
      expect(documents.first["events"].first["sdk"]).to eq(
        {"name" => Aiaiaiai::Errors::SDK_NAME, "version" => Aiaiaiai::Errors::VERSION}
      )
    end

    it "sends only what errors.v1 accepts" do
      configure(endpoint: stub.endpoint)
      validator = Aiaiaiai::Errors::Protocol.validator

      described_class.capture(ArgumentError.new("boom"), error_id: "ai.model.load.failed",
        family_id: "ai.model.availability", context: {"deep" => {"a" => {"b" => {"c" => {"d" => {"e" => "f"}}}}}},
        tags: {"release" => "2026.09.1"})
      described_class.relate(source: "ai.model.load.failed", type: "root_cause_of",
        target: "ai.avatar.response.unavailable", confidence: 0.9, evidence: %w[dependency_failure])
      described_class.flush(timeout: 2.0)

      stub.received.each do |request|
        expect(validator.validate(JSON.parse(request[:body])).map(&:to_s)).to be_empty
      end
    end

    it "scrubs secrets before they leave the host" do
      configure(endpoint: stub.endpoint)

      described_class.report(error_id: "a.one", context: {"password" => "hunter2"})
      described_class.flush(timeout: 2.0)

      expect(stub.received.map { |request| request[:body] }.join).not_to include("hunter2")
    end

    it "does not retry a request the collector has rejected outright" do
      rejecting = StubCollector.new(mode: :unauthorized)
      configure(endpoint: rejecting.endpoint, max_retries: 3)

      described_class.report(error_id: "a.one")
      described_class.flush(timeout: 2.0)
      sleep 0.1

      expect(rejecting.received.length).to eq(1)
      rejecting.stop
    end

    it "stops talking to a collector that keeps failing" do
      failing = StubCollector.new(mode: :server_error)
      configure(endpoint: failing.endpoint, failure_threshold: 2, circuit_reset_after: 30, batch_size: 1)

      10.times { |index| described_class.report(error_id: "a.one", message: "m#{index}") }
      described_class.flush(timeout: 3.0)
      sleep 0.2

      expect(failing.received.length).to be < 10
      expect(described_class.statistics[:circuit]).to eq(:open)
      failing.stop
    end
  end

  describe "shutdown" do
    it "flushes within its bound and then stops" do
      stub = StubCollector.new(mode: :accepted)
      configure(endpoint: stub.endpoint, flush_interval: 0.05)

      described_class.report(error_id: "a.one")
      expect(described_class.shutdown(timeout: 2.0)).to be(true)
      expect(stub.received.length).to eq(1)
      stub.stop
    end

    it "returns within its bound even when the collector never answers" do
      stub = StubCollector.new(mode: :silent)
      configure(endpoint: stub.endpoint, read_timeout: 5.0)

      described_class.report(error_id: "a.one")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.shutdown(timeout: 0.5)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3.0
      stub.stop
    end
  end
end
