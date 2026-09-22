# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "serp_recon"
require "json"

module FixtureHelper
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(path)  = File.read(File.join(FIXTURES, path))
  def fixture?(path) = File.exist?(File.join(FIXTURES, path))
  def fixture_json(path) = JSON.parse(fixture(path))
end

RSpec.configure do |config|
  config.include FixtureHelper
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  # Specs tagged :live hit the network. Excluded from the default rake task so
  # that `rake` stays deterministic and offline; run them with `rake spec_live`.
  config.filter_run_excluding :live unless ENV["LIVE"] == "1"
end
