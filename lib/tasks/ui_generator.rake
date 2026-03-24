namespace :ui do
  desc "Generate a React component using UIGeneratorAgent"
  task :generate, [ :name ] => :environment do |_t, args|
    name = args[:name]

    unless name
      puts "Usage: rake ui:generate[ComponentName]"
      exit 1
    end

    puts "Generating component: #{name}..."

    agent = UIGeneratorAgent.new

    # Component definitions
    components = {
      "VideoTimeline" => {
        description: "A video timeline component that displays video events chronologically. Shows a horizontal timeline with video segments, clickable event markers at their timestamps, and allows reordering. Each video shows its duration and detected events. Includes controls for stitching videos together.",
        props: {
          videos: "Array of video objects with id, title, duration, events",
          events: "Array of event objects with timestamp, type, title, confidence, keyframe_url",
          onEventClick: "Function callback when an event is clicked",
          onReorder: "Function callback when videos are reordered",
          onStitch: "Function callback to stitch videos together",
          totalDuration: "Number - total timeline duration in seconds"
        }
      },
      "VideoUploader" => {
        description: "A drag-and-drop video uploader with progress indication. Shows upload progress, validates file types, and displays video preview thumbnails after upload.",
        props: {
          onUpload: "Function callback when video is uploaded",
          maxSize: "Number - maximum file size in MB",
          acceptedTypes: "Array of accepted MIME types"
        }
      },
      "EventCard" => {
        description: "A card component displaying a single video event with its keyframe image, timestamp, type badge, title, description, and confidence score.",
        props: {
          event: "Event object with timestamp, type, title, description, confidence, keyframe_url",
          onClick: "Function callback when card is clicked",
          isSelected: "Boolean - whether this event is selected"
        }
      }
    }

    config = components[name]
    unless config
      puts "Unknown component: #{name}"
      puts "Available components: #{components.keys.join(', ')}"
      exit 1
    end

    result = agent.generate_component(
      name: name,
      description: config[:description],
      props: config[:props]
    )

    if result[:cached]
      puts "Using cached verified component from: #{result[:path]}"
    else
      puts "Generated new component at: #{result[:path]}"
      puts "\nTo verify and promote to production:"
      puts "  rake ui:verify[#{name}]"
    end
  end

  desc "Verify a generated component and promote to production"
  task :verify, [ :name ] => :environment do |_t, args|
    name = args[:name]

    unless name
      puts "Usage: rake ui:verify[ComponentName]"
      exit 1
    end

    puts "Verifying component: #{name}..."

    agent = UIGeneratorAgent.new
    result = agent.verify_component(name: name)

    if result[:verified]
      puts "Component verified and promoted to: #{result[:path]}"
    else
      puts "Verification failed:"
      result[:errors].each { |e| puts "  - #{e}" }
      puts "\nTo regenerate with feedback:"
      puts "  rake ui:regenerate[#{name},'Your feedback here']"
    end
  end

  desc "Regenerate a component with feedback"
  task :regenerate, [ :name, :feedback ] => :environment do |_t, args|
    name = args[:name]
    feedback = args[:feedback]

    unless name && feedback
      puts "Usage: rake ui:regenerate[ComponentName,'Your feedback']"
      exit 1
    end

    puts "Regenerating component #{name} with feedback..."

    agent = UIGeneratorAgent.new
    result = agent.regenerate_with_feedback(name: name, feedback: feedback)

    if result[:regenerated]
      puts "Component regenerated. Run 'rake ui:verify[#{name}]' to verify."
    else
      puts "Regeneration failed"
    end
  end

  desc "Generate all video analysis components"
  task generate_video_components: :environment do
    %w[VideoTimeline VideoUploader EventCard].each do |name|
      Rake::Task["ui:generate"].reenable
      Rake::Task["ui:generate"].invoke(name)
    end
  end
end
