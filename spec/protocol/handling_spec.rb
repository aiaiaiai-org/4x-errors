# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

RSpec.describe "payload handling" do
  describe Aiaiaiai::Errors::Protocol::Scrubber do
    it "redacts by key, whatever the value looks like" do
      scrubbed = described_class.scrub({"password" => "hunter2", "api_key" => 12345, "note" => "fine"})

      expect(scrubbed).to eq({"password" => "[redacted]", "api_key" => "[redacted]", "note" => "fine"})
    end

    it "redacts credentials embedded in values, keeping the diagnostic part" do
      scrubbed = described_class.scrub({
        "dsn" => "ignored by key",
        "detail" => "connecting to postgres://collector:s3cret@db.example.com/errors failed"
      })

      expect(scrubbed["detail"]).to eq("connecting to postgres://[redacted]@db.example.com/errors failed")
    end

    it "redacts bearer tokens and JSON web tokens found in free text" do
      scrubbed = described_class.scrub([
        "Authorization: Bearer abcdef0123456789",
        "token eyJhbGciOi.eyJzdWIiOiI.SflKxwRJSM"
      ])

      expect(scrubbed).to all(include("[redacted]"))
      expect(scrubbed.join).not_to include("abcdef0123456789")
    end

    it "reaches into nested structures" do
      scrubbed = described_class.scrub({"outer" => {"list" => [{"secret" => "x"}]}})

      expect(scrubbed.dig("outer", "list", 0, "secret")).to eq("[redacted]")
    end
  end

  describe Aiaiaiai::Errors::Protocol::Fingerprint do
    it "keeps a reporter supplied fingerprint" do
      expect(described_class.for({"error_id" => "a.b", "fingerprint" => "sha256:given"})).to eq("sha256:given")
    end

    it "ignores the variable parts of a message" do
      first = described_class.for({"error_id" => "ai.model.load.failed", "message" => "model 41 missing at /var/models/a.bin"})
      second = described_class.for({"error_id" => "ai.model.load.failed", "message" => "model 77 missing at /var/models/b.bin"})

      expect(first).to eq(second)
    end

    it "separates different semantic identities" do
      first = described_class.for({"error_id" => "ai.model.load.failed", "message" => "boom"})
      second = described_class.for({"error_id" => "ai.inference.backend.unavailable", "message" => "boom"})

      expect(first).not_to eq(second)
    end

    it "separates different exception types under one error id" do
      base = {"error_id" => "ai.model.load.failed", "message" => "boom"}
      timeout = described_class.for(base.merge("exception" => {"type" => "Net::ReadTimeout"}))
      refused = described_class.for(base.merge("exception" => {"type" => "Errno::ECONNREFUSED"}))

      expect(timeout).not_to eq(refused)
    end
  end

  describe Aiaiaiai::Errors::Protocol::Bounding do
    let(:limits) { Aiaiaiai::Errors::Protocol::Limits }

    it "truncates long strings" do
      bounded = described_class.context({"blob" => "x" * 10_000})

      expect(bounded["blob"].length).to eq(limits::CONTEXT_STRING_CHARS)
    end

    it "keeps the whole context within its byte budget" do
      bounded = described_class.context((1..500).to_h { |index| ["key#{index}", "v" * 500] })

      expect(JSON.generate(bounded).bytesize).to be <= limits::CONTEXT_BYTES
      expect(bounded["_dropped_keys"]).to be_positive
    end

    it "cuts nesting instead of recursing forever" do
      cyclic = {}
      cyclic["self"] = cyclic

      expect { described_class.context(cyclic) }.not_to raise_error
      expect(JSON.generate(described_class.context(cyclic))).to include("[truncated]")
    end

    it "survives values that cannot describe themselves" do
      hostile = Class.new do
        def to_s = raise("no")

        def inspect = raise("no")
      end.new

      expect(described_class.context({"hostile" => hostile})["hostile"]).to eq("[unserialisable]")
    end

    it "survives invalid encodings" do
      bounded = described_class.context({"bytes" => "caf\xC3".b})

      expect { JSON.generate(bounded) }.not_to raise_error
    end

    it "flattens an exception with its cause chain" do
      inner = ArgumentError.new("inner")
      outer = begin
        begin
          raise inner
        rescue ArgumentError
          raise "outer"
        end
      rescue RuntimeError => error
        error
      end

      flattened = described_class.exception(outer)

      expect(flattened["type"]).to eq("RuntimeError")
      expect(flattened.dig("cause", "type")).to eq("ArgumentError")
      expect(flattened["backtrace"].length).to be <= limits::BACKTRACE_FRAMES
    end

    it "produces a context every bound accepts" do
      validator = Aiaiaiai::Errors::Protocol.validator
      hostile = {"deep" => {"a" => {"b" => {"c" => {"d" => {"e" => {"f" => "g"}}}}}}, "long" => "x" * 9_000}

      payload = {
        "protocol_version" => "errors.v1", "project" => "nilx-one/web",
        "events" => [{"error_id" => "a.b", "environment" => "test",
                      "context" => described_class.context(hostile)}]
      }

      expect(validator.validate(payload)).to be_empty
    end
  end
end
