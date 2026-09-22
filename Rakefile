# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--tag ~live"
end

RSpec::Core::RakeTask.new(:spec_live) do |t|
  t.rspec_opts = "--tag live"
end

task default: :spec
