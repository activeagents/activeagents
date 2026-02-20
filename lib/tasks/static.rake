# frozen_string_literal: true

namespace :static do
  desc "Watch for changes and regenerate static landing page with live reload"
  task watch: :environment do
    require "socket"
    require "fileutils"

    output_dir = Rails.root.join("_site")

    # Generate initial build
    Rake::Task["static:generate"].invoke

    # Inject live reload script into generated HTML
    inject_live_reload(output_dir)

    # Track file modification times
    watch_paths = [
      Rails.root.join("app/views/pages"),
      Rails.root.join("app/views/layouts"),
      Rails.root.join("app/assets/stylesheets/landing"),
      Rails.root.join("public/images"),
      Rails.root.join("public/fonts")
    ].select { |p| Dir.exist?(p) }

    file_mtimes = {}
    watch_paths.each do |dir|
      Dir.glob("#{dir}/**/*").each do |f|
        file_mtimes[f] = File.mtime(f) if File.file?(f)
      end
    end

    # Content types
    content_types = {
      ".html" => "text/html",
      ".css" => "text/css",
      ".js" => "application/javascript",
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".svg" => "image/svg+xml",
      ".ico" => "image/x-icon",
      ".woff" => "font/woff",
      ".woff2" => "font/woff2",
      ".ttf" => "font/ttf",
      ".eot" => "application/vnd.ms-fontobject"
    }

    # SSE clients for live reload
    sse_clients = []

    # Start TCP server in a thread
    server_thread = Thread.new do
      server = TCPServer.new("127.0.0.1", 3333)

      loop do
        client = server.accept
        Thread.new(client) do |c|
          begin
            request = c.gets
            next unless request

            path = request.split(" ")[1]
            path = "/index.html" if path == "/"

            if path == "/live-reload"
              # SSE endpoint
              c.print "HTTP/1.1 200 OK\r\n"
              c.print "Content-Type: text/event-stream\r\n"
              c.print "Cache-Control: no-cache\r\n"
              c.print "Connection: keep-alive\r\n"
              c.print "Access-Control-Allow-Origin: *\r\n"
              c.print "\r\n"
              sse_clients << c
            else
              # Serve static file
              file_path = output_dir.join(path[1..])
              if File.exist?(file_path) && File.file?(file_path)
                ext = File.extname(file_path)
                content_type = content_types[ext] || "application/octet-stream"
                body = File.binread(file_path)

                c.print "HTTP/1.1 200 OK\r\n"
                c.print "Content-Type: #{content_type}\r\n"
                c.print "Content-Length: #{body.bytesize}\r\n"
                c.print "\r\n"
                c.print body
              else
                c.print "HTTP/1.1 404 Not Found\r\n\r\nNot Found"
              end
              c.close
            end
          rescue StandardError
            c.close rescue nil
          end
        end
      rescue Interrupt
        break
      end
    end

    puts "\n🚀 Static site server running at http://localhost:3333"
    puts "👀 Watching for changes...\n\n"

    # Poll for file changes
    loop do
      sleep 1
      changed_files = []

      watch_paths.each do |dir|
        Dir.glob("#{dir}/**/*").each do |f|
          next unless File.file?(f)

          mtime = File.mtime(f)
          if file_mtimes[f] != mtime
            changed_files << File.basename(f)
            file_mtimes[f] = mtime
          end
        end
      end

      next if changed_files.empty?

      puts "🔄 Changed: #{changed_files.join(', ')}"

      # Re-invoke the generate task
      Rake::Task["static:generate"].reenable
      Rake::Task["static:generate"].invoke

      # Re-inject live reload script
      inject_live_reload(output_dir)

      # Notify all SSE clients to reload
      sse_clients.each do |client|
        begin
          client.print "data: reload\n\n"
        rescue StandardError
          sse_clients.delete(client)
        end
      end

      puts "✅ Regenerated and reloading browser...\n\n"
    rescue Interrupt
      break
    end
  end

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

    # Convert absolute paths to relative for GitHub Pages subdirectory deployment
    # This handles /images/, /fonts/, /vendor/, /css/ paths
    html = html.gsub('href="/', 'href="')
    html = html.gsub('src="/', 'src="')
    # Fix the root link to be relative
    html = html.gsub('href=""', 'href="."')

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

def inject_live_reload(output_dir)
  index_path = output_dir.join("index.html")
  return unless File.exist?(index_path)

  html = File.read(index_path)

  live_reload_script = <<~SCRIPT
    <script>
      (function() {
        const evtSource = new EventSource('http://localhost:3333/live-reload');
        evtSource.onmessage = function(e) {
          if (e.data === 'reload') {
            window.location.reload();
          }
        };
        evtSource.onerror = function() {
          console.log('Live reload disconnected, retrying...');
          setTimeout(() => window.location.reload(), 2000);
        };
      })();
    </script>
  SCRIPT

  # Inject before </body> if not already present
  unless html.include?("EventSource('http://localhost:3333/live-reload')")
    html = html.gsub("</body>", "#{live_reload_script}</body>")
    File.write(index_path, html)
  end
end
