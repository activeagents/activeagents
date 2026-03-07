# frozen_string_literal: true

require "io/console"

module Ragents
  module CLI
    # Terminal — raw ANSI escape helpers
    #
    # Charm-inspired aesthetic: rounded borders, gradient header, styled bubbles.
    # Pure stdlib — no ncurses, no Charm Go binaries required.
    module Terminal
      CSI = "\e["

      # Cursor
      def self.hide_cursor    = print "#{CSI}?25l"
      def self.show_cursor    = print "#{CSI}?25h"
      def self.save_cursor    = print "#{CSI}s"
      def self.restore_cursor = print "#{CSI}u"
      def self.move_to(row, col) = print "#{CSI}#{row};#{col}H"
      def self.move_up(n = 1)    = print "#{CSI}#{n}A"
      def self.move_down(n = 1)  = print "#{CSI}#{n}B"
      def self.move_right(n = 1) = print "#{CSI}#{n}C"
      def self.move_left(n = 1)  = print "#{CSI}#{n}D"
      def self.col(n)            = print "#{CSI}#{n}G"

      # Erasure
      def self.clear_screen   = print "#{CSI}2J#{CSI}H"
      def self.clear_line     = print "#{CSI}2K"
      def self.clear_to_eol   = print "#{CSI}K"
      def self.clear_lines(n) = n.times { move_up; clear_line }

      # Text attributes
      RESET     = "#{CSI}0m"
      BOLD      = "#{CSI}1m"
      DIM       = "#{CSI}2m"
      ITALIC    = "#{CSI}3m"
      UNDERLINE = "#{CSI}4m"
      BLINK     = "#{CSI}5m"
      REVERSE   = "#{CSI}7m"

      # True-color (24-bit) — used for the Charm gradient header and accents
      def self.fg_rgb(r, g, b)        = "#{CSI}38;2;#{r};#{g};#{b}m"
      def self.bg_rgb(r, g, b)        = "#{CSI}48;2;#{r};#{g};#{b}m"

      # 256-colour fallback
      def self.fg(code)               = "#{CSI}38;5;#{code}m"
      def self.bg(code)               = "#{CSI}48;5;#{code}m"

      # ── Charm-inspired colour palette ────────────────────────────────────────
      # Mirrors the Lipgloss "Charm" dark theme used in bubbletea apps.
      module Colors
        # Grays
        BASE       = 235   # very dark bg
        SURFACE    = 237   # slightly lighter panel bg
        OVERLAY    = 240   # border / separator
        MUTED      = 244   # secondary text
        TEXT       = 252   # primary text
        BRIGHT     = 255   # emphasized text

        # Charm accent palette (close to charm.sh brand colors)
        PINK       = 212   # #FF87D7  Charm pink
        PINK_DIM   = 175   # muted pink
        LAVENDER   = 147   # #AFAFFF  Charm lavender
        PEACH      = 215   # #FFAF5F  warm orange
        TEAL       = 86    # #5FD7AF  cool teal
        SKY        = 111   # #87AFFF  sky blue
        LIME       = 120   # #87FF87  soft green
        ROSE       = 203   # #FF5F5F  error / warning red

        # Semantic roles
        PROVIDER_OPENAI    = TEAL
        PROVIDER_ANTHROPIC = PEACH
        PROVIDER_OLLAMA    = LAVENDER
        PROVIDER_MOCK      = PINK_DIM
        PROVIDER_DEFAULT   = MUTED

        USER_ACCENT    = SKY
        AGENT_ACCENT   = PINK
        TOOL_ACCENT    = PEACH
        RESULT_ACCENT  = LIME
        SYSTEM_ACCENT  = OVERLAY
        ERROR_ACCENT   = ROSE

        INPUT_FG       = TEXT
        INPUT_CURSOR   = BRIGHT
        BORDER         = OVERLAY
        HINT           = MUTED
        STATUS_KEY     = PINK
        STATUS_DESC    = MUTED

        HEADER_BG      = BASE
      end

      # ── Box-drawing helpers (Charm uses rounded corners everywhere) ───────────
      module Box
        # Rounded border characters
        TL = "╭"
        TR = "╮"
        BL = "╰"
        BR = "╯"
        H  = "─"
        V  = "│"
        # Separators
        LT = "├"
        RT = "┤"
        TT = "┬"
        BT = "┴"

        # Render a rounded box around content lines.
        # content_lines — array of already-styled strings (no trailing newline)
        # width         — total outer width including borders
        # title         — optional styled title for the top border
        def self.render(content_lines, width:, fg:, title: nil)
          inner_w = width - 2
          border_color = Terminal.fg(fg)
          reset = Terminal::RESET

          top = if title
                  plain_title = title.gsub(/\e\[[0-9;]*m/, "")
                  pad = [ inner_w - plain_title.length - 2, 0 ].max
                  "#{border_color}#{TL}#{H} #{reset}#{title}#{border_color} #{H * pad}#{TR}#{reset}"
          else
                  "#{border_color}#{TL}#{H * inner_w}#{TR}#{reset}"
          end

          bottom = "#{border_color}#{BL}#{H * inner_w}#{BR}#{reset}"

          lines = [ top ]
          content_lines.each do |line|
            plain = line.gsub(/\e\[[0-9;]*m/, "")
            pad   = [ inner_w - 2 - plain.length, 0 ].max
            lines << "#{border_color}#{V}#{reset} #{line}#{" " * pad} #{border_color}#{V}#{reset}"
          end
          lines << bottom
          lines
        end

        # A single horizontal rule with optional label
        def self.rule(width, label: nil, fg: Colors::OVERLAY)
          border_color = Terminal.fg(fg)
          reset = Terminal::RESET
          if label
            plain = label.gsub(/\e\[[0-9;]*m/, "")
            left  = (width - plain.length - 4) / 2
            right = width - plain.length - 4 - left
            "#{border_color}#{H * left} #{reset}#{label}#{border_color} #{H * right}#{reset}"
          else
            "#{border_color}#{H * width}#{reset}"
          end
        end
      end

      def self.colored(text, fg_code, bold: false)
        "#{bold ? BOLD : ""}#{fg(fg_code)}#{text}#{RESET}"
      end

      def self.on_bg(text, fg_code, bg_code)
        "#{fg(fg_code)}#{bg(bg_code)}#{text}#{RESET}"
      end

      # Gradient text: interpolates between two RGB tuples across the string
      def self.gradient(text, from_rgb:, to_rgb:)
        chars = text.chars
        n     = [ chars.length - 1, 1 ].max
        chars.each_with_index.map do |ch, i|
          t = i.to_f / n
          r = (from_rgb[0] + (to_rgb[0] - from_rgb[0]) * t).round
          g = (from_rgb[1] + (to_rgb[1] - from_rgb[1]) * t).round
          b = (from_rgb[2] + (to_rgb[2] - from_rgb[2]) * t).round
          "#{fg_rgb(r, g, b)}#{ch}"
        end.join + RESET
      end

      def self.size
        rows, cols = $stdout.winsize
        [ rows, cols ]
      rescue
        [ 24, 80 ]
      end

      def self.width  = size[1]
      def self.height = size[0]
      def self.tty?   = $stdout.isatty
    end

    # =========================================================================
    # TUI — Charm-inspired visual layout
    #
    # Layout (Lipgloss-style, all rounded borders):
    #
    #  ╭─────────────────────────────────────────────────────────────────╮
    #  │  ⚡ ragents    openai · gpt-4o-mini     3 tools  ·  142 tok     │  header
    #  ╰─────────────────────────────────────────────────────────────────╯
    #
    #   ╭── You ──────────────────────────────────────────────────╮
    #   │  Hello, what can you do?                                │
    #   ╰─────────────────────────────────────────────────────────╯
    #
    #   ╭── Agent ────────────────────────────────────────────────╮
    #   │  I can help you with...                                 │
    #   │                                        12in 8out 340ms  │
    #   ╰─────────────────────────────────────────────────────────╯
    #
    #   ◆ search("Ruby Ractors")
    #   ✔ "Found 42 results about..."
    #
    #  ╭──────────────────────────────────────────────────────────╮
    #  │ ❯ _                                      ↵ send  /help   │  input
    #  ╰──────────────────────────────────────────────────────────╯
    #   /help  /tools  /context  /clear  /parallel  /quit         status
    #
    # =========================================================================
    class TUI
      HEADER_HEIGHT = 3   # top box: ╭─╮ + content + ╰─╯  (but drawn as 3 lines)
      STATUS_HEIGHT = 1
      INPUT_HEIGHT  = 3   # ╭─╮ + prompt + ╰─╯
      MIN_CHAT_ROWS = 5

      # Charm brand gradient: pink → lavender
      BRAND_FROM = [ 255, 99,  186 ].freeze   # #FF63BA
      BRAND_TO   = [ 134, 142, 255 ].freeze   # #868EFF

      attr_reader :width, :height, :chat_rows

      def initialize(session)
        @session       = session
        @scroll_offset = 0
        @rendered_lines = []
        refresh_dimensions
      end

      def refresh_dimensions
        @height, @width = Terminal.size
        @chat_rows = [ @height - HEADER_HEIGHT - INPUT_HEIGHT - STATUS_HEIGHT - 1,
                      MIN_CHAT_ROWS ].max
      end

      # ── Full redraw ──────────────────────────────────────────────────────────

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

      # ── Header ───────────────────────────────────────────────────────────────
      # Charm-style: rounded box, gradient brand name, pill-shaped badges

      def draw_header
        t = Terminal
        c = Terminal::Colors
        bw = width - 2   # inner width

        # Brand wordmark with Charm pink→lavender gradient
        brand = "#{Terminal::BOLD}#{t.gradient(" ⚡ ragents ", from_rgb: BRAND_FROM, to_rgb: BRAND_TO)}"

        provider_color = provider_color_code(@session.provider_name)
        sep   = t.colored(" · ", c::OVERLAY)
        pname = t.colored(@session.provider_name, provider_color, bold: true)
        model = t.colored(@session.model_name || "default", c::MUTED)

        left_parts = [ brand, t.colored("│", c::OVERLAY), " #{pname}#{sep}#{model} " ]

        right_parts = []
        right_parts << pill(@session.tool_count.to_s + " tools", c::PEACH)  if @session.tool_count > 0
        right_parts << pill(@session.total_tokens.to_s + " tok",  c::TEAL)  if @session.total_tokens > 0
        right_parts << t.colored("#{@session.message_count} msgs", c::MUTED)

        left_plain  = strip_ansi(left_parts.join)
        right_plain = strip_ansi(right_parts.join(sep))
        gap         = [ bw - left_plain.length - right_plain.length, 0 ].max

        inner = "#{left_parts.join}#{" " * gap}#{right_parts.join(sep)} "

        # Rounded box
        top_border    = "#{t.fg(c::BORDER)}╭#{t.colored("─" * bw, c::BORDER)}╮#{Terminal::RESET}"
        inner_line    = "#{t.fg(c::BORDER)}│#{Terminal::RESET}#{inner}#{t.fg(c::BORDER)}│#{Terminal::RESET}"
        bottom_border = "#{t.fg(c::BORDER)}╰#{t.colored("─" * bw, c::BORDER)}╯#{Terminal::RESET}"

        puts top_border
        puts inner_line
        puts bottom_border
      end

      # ── Chat area ────────────────────────────────────────────────────────────

      def draw_chat_area
        lines = build_chat_lines
        @rendered_lines = lines

        total = lines.length
        @scroll_offset = [ [ total - @chat_rows, 0 ].max, @scroll_offset ].min
        visible = lines[@scroll_offset, @chat_rows] || []

        visible.each { |l| puts l }
        (@chat_rows - visible.length).times { puts "" }
      end

      # ── Build chat lines ─────────────────────────────────────────────────────

      def build_chat_lines # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        t = Terminal
        c = Terminal::Colors
        lines = []
        # Bubble width: narrower than full terminal for visual breathing room
        bw = [ [ width - 6, 40 ].max, width - 4 ].min

        @session.display_messages.each do |msg|
          case msg[:type]

          when :system
            lines << ""
            rule_text = t.colored(" system ", c::MUTED)
            lines << " " + Terminal::Box.rule(bw, label: rule_text, fg: c::OVERLAY)
            wrap(msg[:content], bw - 4).each do |l|
              lines << "  #{t.colored(l, c::MUTED)}"
            end
            lines << " " + Terminal::Box.rule(bw, fg: c::OVERLAY)
            lines << ""

          when :user
            lines << ""
            title = "#{t.fg(c::USER_ACCENT)}#{Terminal::BOLD}You#{Terminal::RESET}"
            content_lines = wrap(msg[:content], bw - 4).map { |l| t.colored(l, c::TEXT) }
            Terminal::Box.render(content_lines, width: bw, fg: c::USER_ACCENT, title: title).each do |l|
              lines << "  #{l}"
            end
            lines << ""

          when :assistant
            lines << ""
            title = "#{t.fg(c::AGENT_ACCENT)}#{Terminal::BOLD}Agent#{Terminal::RESET}"
            content_lines = wrap(msg[:content].to_s, bw - 4).map { |l| t.colored(l, c::BRIGHT) }
            # Append meta line inside the box
            meta = build_assistant_meta(msg, t, c)
            unless meta.empty?
              pad  = [ bw - 4 - strip_ansi(meta).length, 0 ].max
              content_lines << "#{" " * pad}#{meta}"
            end
            Terminal::Box.render(content_lines, width: bw, fg: c::AGENT_ACCENT, title: title).each do |l|
              lines << "  #{l}"
            end
            lines << ""

          when :tool_call
            args_str = format_args(msg[:arguments])
            name_s   = t.colored(msg[:name], c::PEACH, bold: true)
            args_s   = t.colored("(#{args_str})", c::MUTED)
            lines << "   #{t.colored("◆", c::PEACH)} #{name_s}#{args_s}"

          when :tool_result
            icon    = msg[:error] ? t.colored("✖", c::ERROR_ACCENT) : t.colored("✔", c::RESULT_ACCENT)
            content = (msg[:content] || msg[:error] || "").to_s
            preview = content.length > width - 12 ? "#{content[0, width - 15]}…" : content
            lines << "   #{icon} #{t.colored(preview, c::MUTED)}"

          when :error
            lines << ""
            err_title = "#{t.fg(c::ERROR_ACCENT)}#{Terminal::BOLD}Error#{Terminal::RESET}"
            content_lines = wrap(msg[:content], bw - 4).map { |l| t.colored(l, c::ERROR_ACCENT) }
            Terminal::Box.render(content_lines, width: bw, fg: c::ERROR_ACCENT, title: err_title).each do |l|
              lines << "  #{l}"
            end
            lines << ""
          end
        end

        lines << "" if lines.empty?
        lines
      end

      # ── Input box ────────────────────────────────────────────────────────────

      def draw_input_box(buf, cursor_pos)
        t = Terminal
        c = Terminal::Colors
        bw = width - 2

        prompt   = "#{t.fg(c::PINK)}#{Terminal::BOLD}❯#{Terminal::RESET} "
        hint     = @session.thinking? \
                     ? t.colored(" thinking…", c::MUTED) \
                     : t.colored(" ↵ send  /help", c::HINT)

        prompt_plain = strip_ansi(prompt)
        hint_plain   = strip_ansi(hint)
        max_buf = bw - prompt_plain.length - hint_plain.length - 2

        displayed = buf.length > max_buf ? "…#{buf[-(max_buf - 1)..]}" : buf
        cpos      = [ [ cursor_pos, 0 ].max, displayed.length ].min

        before = displayed[0, cpos] || ""
        at     = displayed[cpos] || " "
        after  = displayed[(cpos + 1)..] || ""

        cursor_char = @session.thinking? \
          ? t.colored(at, c::MUTED) \
          : "#{Terminal::REVERSE}#{t.fg(c::INPUT_CURSOR)}#{at}#{Terminal::RESET}"

        input_content = "#{prompt}#{t.colored(before, c::INPUT_FG)}" \
                        "#{cursor_char}" \
                        "#{t.colored(after, c::INPUT_FG)}" \
                        "#{t.colored(" " * [ max_buf - displayed.length, 0 ].max, c::INPUT_FG)}" \
                        "#{hint}"

        top_border    = "#{t.fg(c::BORDER)}╭#{"─" * bw}╮#{Terminal::RESET}"
        inner_line    = "#{t.fg(c::BORDER)}│#{Terminal::RESET}#{input_content}#{t.fg(c::BORDER)}│#{Terminal::RESET}"
        bottom_border = "#{t.fg(c::BORDER)}╰#{"─" * bw}╯#{Terminal::RESET}"

        puts top_border
        puts inner_line
        puts bottom_border
      end

      # ── Status bar ───────────────────────────────────────────────────────────

      def draw_status_bar
        t = Terminal
        c = Terminal::Colors

        shortcuts = [
          [ "/help",     "help" ],
          [ "/tools",    "tools" ],
          [ "/context",  "ctx" ],
          [ "/clear",    "clear" ],
          [ "/parallel", "batch" ],
          [ "/quit",     "quit" ]
        ].map do |cmd, desc|
          "#{t.colored(cmd, c::STATUS_KEY)}#{t.colored(":#{desc}", c::STATUS_DESC)}"
        end.join("  ")

        scroll_hint = @rendered_lines.length > @chat_rows \
          ? "  #{t.colored("alt+↑↓ scroll", c::OVERLAY)}" : ""

        print " #{shortcuts}#{scroll_hint}"
        print Terminal::CSI + "K"   # clear to EOL
      end

      # ── In-place input update (fast keystroke) ───────────────────────────────

      def redraw_input(buf, cursor_pos)
        input_row = HEADER_HEIGHT + @chat_rows + 2  # +2 for separator + box top
        Terminal.move_to(input_row, 1)
        Terminal.clear_line
        draw_input_row(buf, cursor_pos)
      end

      def draw_input_row(buf, cursor_pos)
        t = Terminal
        c = Terminal::Colors
        prompt      = "#{t.fg(c::PINK)}#{Terminal::BOLD}❯#{Terminal::RESET} "
        hint        = @session.thinking? \
                        ? t.colored(" thinking…", c::MUTED) \
                        : t.colored(" ↵ send  /help", c::HINT)
        max_buf     = width - strip_ansi(prompt).length - strip_ansi(hint).length - 4
        displayed   = buf.length > max_buf ? "…#{buf[-(max_buf - 1)..]}" : buf
        cpos        = [ [ cursor_pos, 0 ].max, displayed.length ].min
        before      = displayed[0, cpos] || ""
        at          = displayed[cpos] || " "
        after       = displayed[(cpos + 1)..] || ""
        cursor_char = @session.thinking? \
          ? t.colored(at, c::MUTED) \
          : "#{Terminal::REVERSE}#{t.fg(c::INPUT_CURSOR)}#{at}#{Terminal::RESET}"
        print "#{t.fg(c::BORDER)}│#{Terminal::RESET}#{prompt}" \
              "#{t.colored(before, c::INPUT_FG)}#{cursor_char}#{t.colored(after, c::INPUT_FG)}#{hint}" \
              "#{t.fg(c::BORDER)}│#{Terminal::RESET}"
        Terminal.clear_to_eol
      end

      def scroll(delta)
        max_scroll = [ @rendered_lines.length - @chat_rows, 0 ].max
        @scroll_offset = [ [ @scroll_offset + delta, 0 ].max, max_scroll ].min
      end

      def scroll_to_bottom
        @scroll_offset = [ @rendered_lines.length - @chat_rows, 0 ].max
      end

      private

      # ── Charm "pill" badge ── e.g.  ❮ 3 tools ❯  in accent color ────────────
      def pill(text, color)
        "#{Terminal.fg(color)}#{text}#{Terminal::RESET}"
      end

      def build_assistant_meta(msg, t, c)
        parts = []
        parts << t.colored("#{msg[:input_tokens]}in",  c::SKY)    if msg[:input_tokens]&.positive?
        parts << t.colored("#{msg[:output_tokens]}out", c::LAVENDER) if msg[:output_tokens]&.positive?
        parts << t.colored("#{msg[:duration_ms]}ms",   c::MUTED)  if msg[:duration_ms]&.positive?
        parts.join(t.colored(" · ", c::OVERLAY))
      end

      def format_args(args)
        return "" unless args.is_a?(Hash) && !args.empty?

        args.map do |k, v|
          val = v.to_s
          val = "#{val[0, 27]}…" if val.length > 30
          "#{k}: #{val.inspect}"
        end.join(", ")
      end

      def wrap(text, max_width)
        return [ "" ] if text.nil? || text.empty?

        text.gsub("\r\n", "\n").split("\n").flat_map do |line|
          if line.length <= max_width
            [ line ]
          else
            line.scan(/.{1,#{max_width}}(?:\s|$)|.{1,#{max_width}}/).map(&:rstrip)
          end
        end
      end

      def strip_ansi(str)
        str.to_s.gsub(/\e\[[0-9;]*[mGKHABCDJsurh]/, "")
      end

      def provider_color_code(name)
        c = Terminal::Colors
        case name.to_s.downcase
        when /openai/    then c::PROVIDER_OPENAI
        when /anthropic/ then c::PROVIDER_ANTHROPIC
        when /ollama/    then c::PROVIDER_OLLAMA
        when /mock/      then c::PROVIDER_MOCK
        else                  c::PROVIDER_DEFAULT
        end
      end
    end
  end
end
