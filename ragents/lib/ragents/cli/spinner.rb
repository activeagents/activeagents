# frozen_string_literal: true

module Ragents
  module CLI
    # Spinner — animates a throbber in the input area while the agent is thinking.
    #
    # Runs in a dedicated Thread so it doesn't block the main event loop.
    # The TUI's draw_input_box checks session.thinking? to decide whether to
    # show the spinner or the normal cursor.
    #
    # Usage:
    #   spinner = Spinner.new(tui, session)
    #   spinner.start("Calling gpt-4o-mini")
    #   # ... wait for agent ...
    #   spinner.stop
    #
    # The spinner writes directly to the terminal using ANSI escapes rather
    # than triggering a full redraw, so it is cheap.

    class Spinner
      # Frames cycle through at ~100ms per frame
      FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze
      INTERVAL = 0.1  # seconds between frames

      def initialize(tui, session)
        @tui     = tui
        @session = session
        @thread  = nil
        @running = false
        @label   = ""
        @mutex   = Mutex.new
      end

      # Start the spinner with an optional label.
      # Safe to call multiple times — stops the previous run first.
      def start(label = "Thinking")
        stop
        @label   = label
        @running = true
        @thread  = Thread.new { animate_loop }
        @thread.priority = -1  # lower priority than main thread
      end

      def stop
        return unless @running

        @running = false
        @thread&.join(0.5)
        @thread = nil
        clear_spinner_row
      end

      def running? = @running

      private

      def animate_loop
        frame_idx = 0
        while @running
          draw_frame(FRAMES[frame_idx % FRAMES.length])
          frame_idx += 1
          sleep INTERVAL
        end
      end

      def draw_frame(frame)
        T = Terminal
        C = Terminal::Colors

        # Calculate the input row position (same formula as TUI#draw_input_box)
        rows, = Terminal.size
        input_row = TUI::HEADER_HEIGHT + 1 + @tui.chat_rows + 2

        @mutex.synchronize do
          T.save_cursor
          T.move_to(input_row, 1)
          T.clear_line

          # Render: ❯  ⠋ label…
          prompt_part = T.colored("❯ ", C::RED, bold: true)
          frame_part  = T.colored(frame, C::ORANGE)
          label_part  = T.colored(" #{@label}", C::MID)
          hint_part   = T.colored("  [Ctrl+C to cancel]", C::DIM_C)

          print "#{prompt_part}#{frame_part}#{label_part}#{hint_part}"
          T.clear_to_eol
          T.restore_cursor

          $stdout.flush
        end
      end

      def clear_spinner_row
        T = Terminal
        input_row = TUI::HEADER_HEIGHT + 1 + (@tui&.chat_rows || 10) + 2
        T.save_cursor
        T.move_to(input_row, 1)
        T.clear_line
        T.restore_cursor
        $stdout.flush
      end
    end
  end
end
