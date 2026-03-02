# frozen_string_literal: true

require "io/console"

module Ragents
  module CLI
    # Terminal — raw ANSI escape helpers
    #
    # All output goes through this module so we have one place to control
    # whether we're writing to a real TTY or piped stdout.
    module Terminal
      # ANSI escape sequences
      CSI = "\e["

      # Cursor
      def self.hide_cursor  = print "#{CSI}?25l"
      def self.show_cursor  = print "#{CSI}?25h"
      def self.save_cursor  = print "#{CSI}s"
      def self.restore_cursor = print "#{CSI}u"

      def self.move_to(row, col) = print "#{CSI}#{row};#{col}H"
      def self.move_up(n = 1)    = print "#{CSI}#{n}A"
      def self.move_down(n = 1)  = print "#{CSI}#{n}B"
      def self.move_right(n = 1) = print "#{CSI}#{n}C"
      def self.move_left(n = 1)  = print "#{CSI}#{n}D"

      def self.col(n)            = print "#{CSI}#{n}G"  # move to column N

      # Erasure
      def self.clear_screen      = print "#{CSI}2J#{CSI}H"
      def self.clear_line        = print "#{CSI}2K"
      def self.clear_to_eol      = print "#{CSI}K"
      def self.clear_lines(n)
        n.times { move_up; clear_line }
      end

      # Attributes
      RESET     = "#{CSI}0m"
      BOLD      = "#{CSI}1m"
      DIM       = "#{CSI}2m"
      ITALIC    = "#{CSI}3m"
      UNDERLINE = "#{CSI}4m"
      BLINK     = "#{CSI}5m"
      REVERSE   = "#{CSI}7m"

      # 256-colour foreground (works on every modern terminal)
      def self.fg(code)           = "#{CSI}38;5;#{code}m"
      def self.bg(code)           = "#{CSI}48;5;#{code}m"

      # Named 256-colour palette used throughout the TUI
      module Colors
        RED       = 196
        RED_SOFT  = 203
        ORANGE    = 208
        YELLOW    = 220
        GREEN     = 46
        GREEN_DIM = 34
        CYAN      = 51
        BLUE      = 69
        PURPLE    = 135
        PINK      = 211
        WHITE     = 255
        LIGHT     = 252
        MID       = 245
        DIM_C     = 238
        DARK      = 234
        BLACK     = 232

        PROVIDER_OPENAI    = CYAN
        PROVIDER_ANTHROPIC = ORANGE
        PROVIDER_MOCK      = PURPLE
        PROVIDER_DEFAULT   = MID

        USER_BUBBLE   = BLUE
        AGENT_BUBBLE  = RED_SOFT
        TOOL_BUBBLE   = YELLOW
        SYSTEM_BUBBLE = DIM_C
        ERROR_BUBBLE  = RED

        HEADER_BG = DARK
        INPUT_FG  = WHITE
        BORDER    = DIM_C
        MUTED     = MID
        STATUS    = GREEN_DIM
      end

      def self.colored(text, fg_code, bold: false)
        "#{bold ? BOLD : ""}#{fg(fg_code)}#{text}#{RESET}"
      end

      def self.on_bg(text, fg_code, bg_code)
        "#{fg(fg_code)}#{bg(bg_code)}#{text}#{RESET}"
      end

      # Terminal dimensions
      def self.size
        if $stdout.respond_to?(:winsize)
          rows, cols = $stdout.winsize
          [rows, cols]
        else
          [24, 80]
        end
      rescue
        [24, 80]
      end

      def self.width  = size[1]
      def self.height = size[0]

      def self.tty? = $stdout.isatty
    end

    # =========================================================================
    # TUI — the visual layout engine
    #
    # Renders a split layout:
    #
    #   ┌──────────────────────────────────────────────────────┐
    #   │ ⚡ ragents  │ gpt-4o-mini │ 3 tools │ 142 tok        │  ← header
    #   ├──────────────────────────────────────────────────────┤
    #   │                                                      │
    #   │   [System] You are a helpful assistant.              │  ← chat
    #   │                                                      │  ← scroll
    #   │   You  Hello, what can you do?                       │  ← area
    #   │                                                      │
    #   │   Agent  I can help with...         12tok  340ms     │
    #   │                                                      │
    #   │   ◎ Tool: search("Ruby Ractors")                     │
    #   │   ✓ Tool result: "Found 42 results"                  │
    #   │                                                      │
    #   ├──────────────────────────────────────────────────────┤
    #   │ ❯  _                                           [↵ send]│  ← input
    #   └──────────────────────────────────────────────────────┘
    #   │ /help · /tools · /context · /clear · /quit          │  ← status
    #
    # On non-TTY stdout (piped), falls back to plain line mode.
    # =========================================================================
    class TUI
      HEADER_HEIGHT = 1
      STATUS_HEIGHT = 1
      INPUT_HEIGHT  = 3   # border + prompt + border
      MIN_CHAT_ROWS = 5

      attr_reader :width, :height, :chat_rows

      def initialize(session)
        @session      = session
        @scroll_offset = 0
        @rendered_lines = []  # current logical chat lines
        refresh_dimensions
      end

      # ── Layout ─────────────────────────────────────────────────────────────

      def refresh_dimensions
        @height, @width = Terminal.size
        @chat_rows = [@height - HEADER_HEIGHT - INPUT_HEIGHT - STATUS_HEIGHT - 2, MIN_CHAT_ROWS].max
      end

      # ── Full redraw ─────────────────────────────────────────────────────────

      def draw_all(input_buf, cursor_pos)
        refresh_dimensions
        Terminal.hide_cursor
        Terminal.move_to(1, 1)

        draw_header
        draw_chat_area
        draw_input_box(input_buf, cursor_pos)
        draw_status_bar

        Terminal.show_cursor
      end

      # ── Header ──────────────────────────────────────────────────────────────

      def draw_header
        T = Terminal
        C = Terminal::Colors

        provider_color = provider_color_code(@session.provider_name)
        total_tokens   = @session.total_tokens

        left = [
          T.colored(" ⚡ ragents ", C::RED, bold: true),
          T.colored("│", C::BORDER),
          " #{T.colored(@session.provider_name, provider_color)} ",
          T.colored("│", C::BORDER),
          " #{T.colored(@session.model_name || "default", C::MID)} "
        ].join

        right_parts = []
        if @session.tool_count > 0
          right_parts << T.colored("#{@session.tool_count} tools", C::YELLOW)
        end
        if total_tokens > 0
          right_parts << T.colored("#{total_tokens} tok", C::CYAN)
        end
        right_parts << T.colored("#{@session.message_count} msgs", C::MID)

        right = right_parts.join(T.colored(" · ", C::BORDER)) + " "

        # Pad to fill width
        left_plain  = strip_ansi(left)
        right_plain = strip_ansi(right)
        padding     = [width - left_plain.length - right_plain.length, 0].max

        line = "#{T.bg(C::HEADER_BG)}#{left}#{" " * padding}#{right}#{Terminal::RESET}"
        puts line
        puts T.colored("─" * width, C::BORDER)
      end

      # ── Chat area ───────────────────────────────────────────────────────────

      def draw_chat_area
        T = Terminal
        C = Terminal::Colors

        # Build all logical display lines
        lines = build_chat_lines
        @rendered_lines = lines

        # Scroll: show last @chat_rows lines by default
        total = lines.length
        @scroll_offset = [[total - @chat_rows, 0].max, @scroll_offset].min
        visible = lines[@scroll_offset, @chat_rows] || []

        # Render each line, pad to @chat_rows
        visible.each { |l| puts l }
        padding = @chat_rows - visible.length
        padding.times { puts "" }
      end

      # ── Build logical display lines from session messages ─────────────────

      def build_chat_lines  # rubocop:disable Metrics/MethodLength
        T = Terminal
        C = Terminal::Colors
        lines = []
        w = [width - 4, 20].max  # usable width after margins

        @session.display_messages.each do |msg|
          case msg[:type]
          when :system
            lines << ""
            lines << "  #{T.colored("┄ System ┄", C::DIM_C)}"
            wrap(msg[:content], w - 4).each do |l|
              lines << "  #{T.colored("  #{l}", C::DIM_C)}"
            end
            lines << ""

          when :user
            lines << ""
            label = T.colored("  You", C::USER_BUBBLE, bold: true)
            wrap(msg[:content], w - 8).each_with_index do |l, i|
              lines << (i.zero? ? "#{label}  #{T.colored(l, C::WHITE)}" : "        #{T.colored(l, C::WHITE)}")
            end

          when :assistant
            lines << ""
            label = T.colored("  Agent", C::AGENT_BUBBLE, bold: true)
            meta  = build_assistant_meta(msg, T, C)
            wrap(msg[:content].to_s, w - 8).each_with_index do |l, i|
              if i.zero?
                lines << "#{label}  #{T.colored(l, C::LIGHT)}"
              else
                lines << "        #{T.colored(l, C::LIGHT)}"
              end
            end
            lines << "        #{meta}" unless meta.empty?

          when :tool_call
            args_str = format_args(msg[:arguments])
            lines << "  #{T.colored("◎", C::YELLOW)} #{T.colored("Tool:", C::YELLOW, bold: true)} #{T.colored(msg[:name], C::WHITE)}#{T.colored("(#{args_str})", C::MID)}"

          when :tool_result
            icon    = msg[:error] ? T.colored("✗", C::ERROR_BUBBLE) : T.colored("✓", C::GREEN_DIM)
            content = (msg[:content] || msg[:error] || "").to_s
            preview = content.length > 80 ? "#{content[0, 77]}…" : content
            lines << "  #{icon} #{T.colored("Result:", C::MID)} #{T.colored(preview, C::DIM_C)}"

          when :error
            lines << ""
            lines << "  #{T.colored("⚠ Error:", C::ERROR_BUBBLE, bold: true)} #{T.colored(msg[:content], C::ERROR_BUBBLE)}"
            lines << ""
          end
        end

        lines << "" if lines.empty?
        lines
      end

      # ── Input box ───────────────────────────────────────────────────────────

      def draw_input_box(buf, cursor_pos)
        T = Terminal
        C = Terminal::Colors

        puts T.colored("─" * width, C::BORDER)

        # Prompt line with buffer content
        prompt   = T.colored("❯ ", C::RED, bold: true)
        hint     = T.colored(@session.thinking? ? " [thinking…]" : " [↵ send  /help]", C::DIM_C)
        max_buf  = width - strip_ansi(prompt).length - strip_ansi(hint).length - 2

        displayed = buf.length > max_buf ? "…#{buf[-(max_buf - 1)..] }" : buf
        cursor_display = cursor_pos > displayed.length ? displayed.length : cursor_pos

        # Build the line with a visible cursor block
        before_cursor = displayed[0, cursor_display] || ""
        at_cursor     = displayed[cursor_display] || " "
        after_cursor  = displayed[(cursor_display + 1)..] || ""

        cursor_char = @session.thinking? ? T.colored(at_cursor, C::DIM_C) : "#{Terminal::REVERSE}#{at_cursor}#{Terminal::RESET}"

        print prompt
        print T.colored(before_cursor, C::INPUT_FG)
        print cursor_char
        print T.colored(after_cursor, C::INPUT_FG)
        print T.colored(" " * [max_buf - displayed.length, 0].max, C::INPUT_FG)
        puts hint

        puts T.colored("─" * width, C::BORDER)
      end

      # ── Status bar ──────────────────────────────────────────────────────────

      def draw_status_bar
        T = Terminal
        C = Terminal::Colors

        shortcuts = [
          ["/help", "commands"],
          ["/tools", "list tools"],
          ["/context", "show ctx"],
          ["/clear", "new chat"],
          ["/parallel", "batch run"],
          ["/quit", "exit"]
        ].map { |cmd, desc| "#{T.colored(cmd, C::RED)}#{T.colored(":#{desc}", C::MID)}" }.join("  ")

        scroll_hint = @rendered_lines.length > @chat_rows ? T.colored("  scroll: alt+↑↓", C::DIM_C) : ""

        print T.colored(" ", C::MUTED)
        print shortcuts
        print scroll_hint
        print T.clear_to_eol
      end

      # ── In-place update helpers ──────────────────────────────────────────────

      # Redraw just the input line (for fast keystroke feedback)
      def redraw_input(buf, cursor_pos)
        T = Terminal
        # Move to input row (header + separator + chat_rows + separator = header+1+chat_rows+1 lines)
        input_row = HEADER_HEIGHT + 1 + @chat_rows + 2
        T.move_to(input_row, 1)
        T.clear_line
        draw_input_row(buf, cursor_pos)
      end

      def draw_input_row(buf, cursor_pos)
        T = Terminal
        C = Terminal::Colors
        prompt   = T.colored("❯ ", C::RED, bold: true)
        hint     = T.colored(@session.thinking? ? " [thinking…]" : " [↵ send  /help]", C::DIM_C)
        max_buf  = width - strip_ansi(prompt).length - strip_ansi(hint).length - 2
        displayed = buf.length > max_buf ? "…#{buf[-(max_buf - 1)..]}" : buf
        cursor_display = [[cursor_pos, 0].max, displayed.length].min
        before_cursor = displayed[0, cursor_display] || ""
        at_cursor     = displayed[cursor_display] || " "
        after_cursor  = displayed[(cursor_display + 1)..] || ""
        cursor_char   = @session.thinking? ? T.colored(at_cursor, C::DIM_C) : "#{Terminal::REVERSE}#{at_cursor}#{Terminal::RESET}"
        print "#{prompt}#{T.colored(before_cursor, C::INPUT_FG)}#{cursor_char}#{T.colored(after_cursor, C::INPUT_FG)}#{hint}"
        T.clear_to_eol
      end

      # Scroll the chat area
      def scroll(delta)
        max_scroll = [@rendered_lines.length - @chat_rows, 0].max
        @scroll_offset = [[@scroll_offset + delta, 0].max, max_scroll].min
      end

      def scroll_to_bottom
        @scroll_offset = [@rendered_lines.length - @chat_rows, 0].max
      end

      private

      def build_assistant_meta(msg, t, c)
        parts = []
        parts << t.colored("#{msg[:input_tokens]}in", c::BLUE)      if msg[:input_tokens]&.positive?
        parts << t.colored("#{msg[:output_tokens]}out", c::PURPLE)  if msg[:output_tokens]&.positive?
        parts << t.colored("#{msg[:duration_ms]}ms", c::MID)        if msg[:duration_ms]&.positive?
        parts.join(t.colored(" · ", c::BORDER))
      end

      def format_args(args)
        return "" unless args.is_a?(Hash) && !args.empty?

        args.map do |k, v|
          val = v.to_s
          val = val.length > 30 ? "#{val[0, 27]}…" : val
          "#{k}: #{val.inspect}"
        end.join(", ")
      end

      # Word-wrap text to max_width characters
      def wrap(text, max_width)
        return [""] if text.nil? || text.empty?

        text.gsub("\r\n", "\n").split("\n").flat_map do |line|
          if line.length <= max_width
            [line]
          else
            line.scan(/.{1,#{max_width}}(?:\s|$)|.{1,#{max_width}}/).map(&:rstrip)
          end
        end
      end

      # Strip ANSI escape codes for length calculation
      def strip_ansi(str)
        str.to_s.gsub(/\e\[[0-9;]*[mGKHABCDJsurh]/, "")
      end

      def provider_color_code(name)
        case name.to_s.downcase
        when /openai/    then Terminal::Colors::PROVIDER_OPENAI
        when /anthropic/ then Terminal::Colors::PROVIDER_ANTHROPIC
        when /mock/      then Terminal::Colors::PROVIDER_MOCK
        else                  Terminal::Colors::PROVIDER_DEFAULT
        end
      end
    end
  end
end
