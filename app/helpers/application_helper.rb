module ApplicationHelper
  # Inline an SVG file so CSS can target elements within it
  # Usage: <%= inline_svg("activeagent-hero.svg") %>
  def inline_svg(filename, options = {})
    file_path = Rails.root.join("public", "images", filename)
    return "" unless File.exist?(file_path)

    svg = File.read(file_path)
    svg = svg.gsub(/<!--.*?-->/m, "") if options[:strip_comments]
    svg.html_safe
  end
end
