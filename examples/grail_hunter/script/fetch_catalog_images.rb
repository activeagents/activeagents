#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads the sample catalog's remote pictures into public/catalog/images so
# the seed data works offline, rewrites config/catalog.yml to the local paths,
# and writes public/catalog/images/CREDITS.md from each entry's image_credit.
#
#   bin/rails runner script/fetch_catalog_images.rb
#
# Needs outbound access to the image hosts (upload.wikimedia.org for the
# Wikimedia Commons pictures the catalog ships with). Entries whose image_url
# is already local, or has no http(s) scheme, are left alone. Safe to re-run.

require "net/http"
require "yaml"
require "fileutils"
require "digest"

catalog_path = Rails.root.join("config/catalog.yml")
images_dir = Rails.root.join("public/catalog/images")
FileUtils.mkdir_p(images_dir)

entries = YAML.load_file(catalog_path, permitted_classes: [ Date ])
user_agent = "GrailHunterSeed/1.0 (+https://github.com/activeagents/activeagent) catalog image fetch"

fetched = 0
entries.each do |entry|
  url = entry["image_url"].to_s
  next unless url.start_with?("http")

  slug = entry["url"].to_s.split("/").last
  extension = File.extname(URI(url).path).downcase.presence_in(%w[.jpg .jpeg .png .webp]) || ".jpg"
  filename = "#{slug}#{extension}"
  target = images_dir.join(filename)

  unless target.exist?
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = user_agent
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      warn "#{slug}: HTTP #{response.code} for #{url}; kept the remote URL"
      next
    end
    File.binwrite(target, response.body)
  end

  entry["image_remote_url"] = url
  entry["image_url"] = "/catalog/images/#{filename}"
  fetched += 1
end

File.write(catalog_path, entries.to_yaml(line_width: -1))

credits = entries.select { |entry| entry["image_credit"].present? }.map do |entry|
  "- #{entry['title']}: #{entry['image_credit']}#{entry['image_source'] && " (#{entry['image_source']})"}"
end
File.write(images_dir.join("CREDITS.md"), <<~MD)
  # Catalog image credits

  Pictures for the sample listings in config/catalog.yml, fetched by
  script/fetch_catalog_images.rb. Each is used under the licence named here;
  the link is the file's source page.

  #{credits.join("\n")}
MD

puts "Downloaded #{fetched} picture#{'s' unless fetched == 1} into #{images_dir.relative_path_from(Rails.root)}."
