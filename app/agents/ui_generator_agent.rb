# UIGeneratorAgent - Generates React UI components using LLM and caches verified versions
#
# Uses the VLM to generate clean, working React components dynamically.
# Once a component is verified (renders correctly, looks clean), it gets cached
# as a static file for production use.
#
# Example usage:
#   UIGeneratorAgent.new.generate_component(
#     name: "VideoTimeline",
#     description: "A timeline showing video events chronologically",
#     props: { events: [], videos: [], onEventClick: "function" }
#   )
#
class UIGeneratorAgent < ApplicationAgent
  generate_with :anthropic, model: "claude-sonnet-5"

  CACHE_DIR = Rails.root.join("app/javascript/components/generated")
  VERIFIED_DIR = Rails.root.join("app/javascript/components/dashboard")

  def initialize
    FileUtils.mkdir_p(CACHE_DIR)
    super
  end

  # Generate a new React component
  def generate_component(name:, description:, props: {}, design_system: :tailwind)
    # Check if we have a verified cached version
    cached_path = verified_component_path(name)
    if File.exist?(cached_path)
      Rails.logger.info "Using cached verified component: #{name}"
      return { cached: true, path: cached_path }
    end

    # Generate new component with LLM
    component_code = generate_with_llm(name, description, props, design_system)

    # Save to cache directory for testing
    cache_path = save_to_cache(name, component_code)

    {
      cached: false,
      path: cache_path,
      code: component_code,
      needs_verification: true
    }
  end

  # Verify a generated component works correctly
  def verify_component(name:, test_props: {})
    cache_path = cached_component_path(name)
    return { error: "Component not found in cache" } unless File.exist?(cache_path)

    # Run component render test (could use Playwright for visual verification)
    render_result = test_render(name, test_props)

    if render_result[:success]
      # Move to verified directory
      promote_to_verified(name)
      { verified: true, path: verified_component_path(name) }
    else
      { verified: false, errors: render_result[:errors] }
    end
  end

  # Regenerate a component with feedback
  def regenerate_with_feedback(name:, feedback:)
    current_code = File.read(cached_component_path(name)) rescue nil

    improved_code = improve_with_feedback(name, current_code, feedback)
    save_to_cache(name, improved_code)

    { regenerated: true, code: improved_code }
  end

  private

  def generate_with_llm(name, description, props, design_system)
    props_spec = props.map { |k, v| "  #{k}: #{v}" }.join("\n")

    response = prompt(
      message: build_generation_prompt(name, description, props_spec, design_system)
    )

    # Extract code from response
    extract_component_code(response)
  end

  def build_generation_prompt(name, description, props_spec, design_system)
    <<~PROMPT
      Generate a React component with the following specifications:

      Component Name: #{name}
      Description: #{description}

      Props:
      #{props_spec}

      Design System: #{design_system}

      Requirements:
      1. Use React functional components with hooks
      2. Use Tailwind CSS for styling (no external CSS files)
      3. Make it responsive and accessible
      4. Include proper TypeScript-style prop validation with PropTypes or JSDoc
      5. Handle loading and empty states gracefully
      6. Use semantic HTML elements
      7. Include helpful comments for complex logic
      8. Export as default

      Style Guidelines:
      - Clean, minimal design
      - Consistent spacing (use Tailwind's spacing scale)
      - Good color contrast for accessibility
      - Smooth hover/focus states
      - Mobile-first responsive design

      Return ONLY the component code wrapped in ```jsx``` tags.
      Do not include any explanation before or after the code.
    PROMPT
  end

  def improve_with_feedback(name, current_code, feedback)
    response = prompt(
      message: <<~PROMPT
        Improve this React component based on the following feedback:

        Current Component (#{name}):
        ```jsx
        #{current_code}
        ```

        Feedback:
        #{feedback}

        Return ONLY the improved component code wrapped in ```jsx``` tags.
        Maintain the same component name and props interface.
      PROMPT
    )

    extract_component_code(response)
  end

  def extract_component_code(response)
    # Extract code between ```jsx and ``` markers
    match = response.match(/```jsx\s*([\s\S]*?)```/)
    match ? match[1].strip : response.strip
  end

  def save_to_cache(name, code)
    path = cached_component_path(name)
    File.write(path, code)
    Rails.logger.info "Saved generated component to cache: #{path}"
    path
  end

  def promote_to_verified(name)
    source = cached_component_path(name)
    dest = verified_component_path(name)

    FileUtils.cp(source, dest)
    Rails.logger.info "Promoted component to verified: #{dest}"
  end

  def cached_component_path(name)
    CACHE_DIR.join("#{name}.jsx")
  end

  def verified_component_path(name)
    VERIFIED_DIR.join("#{name}.jsx")
  end

  def test_render(name, props)
    # Basic syntax check - in production you'd use a real renderer
    code = File.read(cached_component_path(name))

    # Check for common issues
    errors = []
    errors << "Missing export default" unless code.include?("export default")
    errors << "Missing return statement" unless code.include?("return")
    errors << "Unclosed JSX tags" if code.scan(/<(\w+)/).size != code.scan(/<\/\w+>/).size + code.scan(/\/>/).size

    { success: errors.empty?, errors: errors }
  end
end
