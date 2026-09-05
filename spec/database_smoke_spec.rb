# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'sequel'

RSpec.describe 'PostgreSQL test boundary' do
  it 'connects only through the dedicated test database URL' do
    database = Sequel.connect(ENV.fetch('TEST_DATABASE_URL'))

    expect(database.get(Sequel.lit('1'))).to eq(1)
  ensure
    database&.disconnect
  end
end
