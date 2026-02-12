# frozen_string_literal: true

namespace :static do
  desc "Generate static landing page for GitHub Pages deployment"
  task generate: :environment do
    require "fileutils"

    output_dir = Rails.root.join("_site")
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)

    # Render the landing page
    html = ApplicationController.render(
      template: "pages/home",
      layout: "landing_static",
      assigns: {}
    )

    # Write the HTML file
    File.write(output_dir.join("index.html"), html)
    puts "Generated: _site/index.html"

    # Copy static assets
    %w[fonts images vendor].each do |dir|
      src = Rails.root.join("public", dir)
      if Dir.exist?(src)
        FileUtils.cp_r(src, output_dir)
        puts "Copied: #{dir}/"
      end
    end

    # Copy CSS
    FileUtils.mkdir_p(output_dir.join("css"))
    css_src = Rails.root.join("app/assets/stylesheets/landing")
    if Dir.exist?(css_src)
      Dir.glob(css_src.join("*.css")).each do |file|
        FileUtils.cp(file, output_dir.join("css"))
        puts "Copied: css/#{File.basename(file)}"
      end
    end

    puts "\nStatic site generated in _site/"
  end
end
