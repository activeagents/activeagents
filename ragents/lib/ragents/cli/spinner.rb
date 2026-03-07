# frozen_string_literal: true

module Ragents
  module CLI
    # Spinner — animated throbber rendered inside the input box while thinking.
    #
    # Charm-style: uses the "dots" animation (⣾⣽⣻⢿⡿⣟⣯⣷) with a gradient label
    # that cycles through the Charm pink→lavender brand palette.
    #
    # Runs in a background Thread, writes directly to the input row via ANSI
    # save/restore cursor so no full redraw is needed.

    class Spinner
      # Charm "dots" frames — same as bubbletea's spinner.Dot
      FRAMES = %w[⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷].freeze

      # Label gradient steps (pink → lavender, 8 steps)
      GRADIENT_STEPS = [
        [ 255,  99, 186 ],  # #FF63BA  pink
        [ 255, 112, 192 ],
        [ 240, 120, 220 ],
        [ 210, 128, 240 ],
        [ 180, 133, 255 ],
        [ 160, 138, 255 ],
        [ 147, 142, 255 ],  # #938EFF  lavender
        [ 134, 142, 255 ]   # #868EFF
      ].freeze

      INTERVAL = 0.08  # seconds — slightly faster than braille for dot style

      def initialize(tui, session)
        @tui     = tui
        @session = session
        @thread  = nil
        @running = false
        @label   = ""
        @mutex   = Mutex.new
      end

      def start(label = "Thinking")
        stop
        @label   = label
        @running = true
        @thread  = Thread.new { animate_loop }
        @thread.priority = -1
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
        color_idx = 0
        while @running
          draw_frame(FRAMES[frame_idx % FRAMES.length], GRADIENT_STEPS[color_idx % GRADIENT_STEPS.length])
          frame_idx  += 1
          color_idx  += 1
          sleep INTERVAL
        end
      end

      def draw_frame(frame, rgb)
        t = Terminal
        c = Terminal::Colors

        input_row = TUI::HEADER_HEIGHT + @tui.chat_rows + 2  # same formula as input box inner line

        @mutex.synchronize do
          t.save_cursor
          t.move_to(input_row, 1)
          t.clear_line

          r, g, b   = rgb
          frame_s   = "#{Terminal::BOLD}#{t.fg_rgb(r, g, b)}#{frame}#{Terminal::RESET}"
          label_s   = t.colored(" #{@label}", c::MUTED)
          cancel_s  = t.colored("   ctrl+c to cancel", c::OVERLAY)
          border_fg = t.fg(c::BORDER)
          reset     = Terminal::RESET

          print "#{border_fg}│#{reset} #{frame_s}#{label_s}#{cancel_s}"
          t.clear_to_eol
          print "  #{border_fg}│#{reset}"
          t.restore_cursor
          $stdout.flush
        end
      end

      def clear_spinner_row
        t = Terminal
        input_row = TUI::HEADER_HEIGHT + (@tui&.chat_rows || 10) + 2
        t.save_cursor
        t.move_to(input_row, 1)
        t.clear_line
        t.restore_cursor
        $stdout.flush
      end
    end
  end
end
