#!/usr/bin/env ruby
# frozen_string_literal: true

# Re-record a fixture. Fixtures are recorded, never hand-written, so that a
# layout change is reproduced exactly rather than approximated.
#
#   ruby bin/record_fixture.rb wikipedia "ruby programming"
#   ruby bin/record_fixture.rb google_books "ruby programming" $GOOGLE_BOOKS_KEY

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "serp_recon"
require "fileutils"

engine = ARGV.shift or abort("usage: record_fixture.rb <engine> <query> [api_key]")
query  = ARGV.shift or abort("usage: record_fixture.rb <engine> <query> [api_key]")
key    = ARGV.shift

slug = query.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
dir  = File.expand_path("../spec/fixtures/#{engine}", __dir__)
FileUtils.mkdir_p(dir)

case engine
when "wikipedia"
  eng = SerpRecon::Engines::Wikipedia.new(q: query)
  fetcher = SerpRecon::Fetcher.new
  File.write(File.join(dir, "#{slug}.html"), fetcher.get(eng.url).body)
  File.write(File.join(dir, "#{slug}.api.json"), fetcher.get(eng.api_url).body)
  puts "recorded #{slug}.html + #{slug}.api.json"
when "google_books"
  abort("google_books needs an API key: the keyless quota is shared and usually exhausted") unless key
  eng = SerpRecon::Engines::GoogleBooks.new(q: query, api_key: key)
  File.write(File.join(dir, "volumes.json"), SerpRecon::Fetcher.new.get(eng.url).body)
  puts "recorded volumes.json"
else
  abort("unknown engine #{engine}")
end
