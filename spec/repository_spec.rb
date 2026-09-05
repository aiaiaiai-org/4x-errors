# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

# Repository level invariants that are easy to state and easy to break.
RSpec.describe "the repository" do
  root = File.expand_path("..", __dir__)

  def read(root, path)
    File.read(File.join(root, path), encoding: "UTF-8")
  end

  describe "the Ruby version" do
    it "is pinned to a stable Ruby 4.x in .ruby-version" do
      expect(read(root, ".ruby-version").strip).to match(/\A4\.\d+\.\d+\z/)
    end

    it "is the same version the container image builds on" do
      pinned = read(root, ".ruby-version").strip
      dockerfile = read(root, "Dockerfile")

      expect(dockerfile).to include("ARG RUBY_VERSION=#{pinned}")
    end

    it "is taken from the pin by every workflow, never retyped" do
      Dir[File.join(root, ".github/workflows/*.yml")].each do |workflow|
        content = File.read(workflow, encoding: "UTF-8")
        next unless content.include?("ruby/setup-ruby")

        expect(content).to include("ruby-version-file: .ruby-version")
        expect(content).not_to match(/ruby-version:\s*\d/)
      end
    end
  end

  describe "copyright" do
    signature = "© 2026 aiaiaiai · aiaiaiai.org"

    authored = Dir[
      File.join(root, "lib/**/*.{rb,rake}"),
      File.join(root, "spec/**/*.rb"),
      File.join(root, "db/**/*.rb"),
      File.join(root, "config/**/*.rb"),
      File.join(root, "Rakefile"),
      File.join(root, "Gemfile"),
      File.join(root, "config.ru"),
      File.join(root, "Dockerfile")
    ].reject { |path| path.include?("/vendor/") }

    it "covers every authored source file" do
      missing = authored.reject { |path| File.read(path, encoding: "UTF-8").include?(signature) }

      expect(missing.map { |path| path.delete_prefix("#{root}/") }).to be_empty
    end

    it "asserts no licence, because the repository has not selected one" do
      # Assembled so that this example does not match itself.
      marker = %w[SPDX License Identifier].join("-")
      offenders = authored.select { |path| File.read(path, encoding: "UTF-8").include?(marker) }

      expect(offenders).to be_empty
    end
  end

  describe "credentials" do
    it "keeps no environment file in the repository" do
      expect(Dir[File.join(root, ".env*")].reject { |path| path.end_with?(".example") }).to be_empty
    end

    it "never renders a database password, whatever it is given" do
      redacted = Aiaiaiai::Errors::Collector::Database.redact("postgres://collector:s3cret@db.example.com:5432/errors")

      expect(redacted).not_to include("s3cret")
      expect(redacted).to eq("postgres://collector:***@db.example.com:5432/errors")
    end

    it "requires TLS to anything that is not the local machine" do
      normalised = Aiaiaiai::Errors::Collector::Database.require_tls("postgres://u:p@db.rqujdfqncgmxhfacajbz.supabase.co/postgres")

      expect(normalised).to end_with("sslmode=require")
    end

    it "leaves a local development database alone" do
      local = "postgres://postgres@127.0.0.1:5432/4x_errors_test"

      expect(Aiaiaiai::Errors::Collector::Database.require_tls(local)).to eq(local)
    end
  end
end
