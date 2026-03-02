# frozen_string_literal: true

require "io/console"
require "io/wait"

module Ragents
  module CLI
    # InputHandler — reads keystrokes in raw mode and produces InputEvent objects.
    #
    # Handles:
    #   - Printable ASCII + UTF-8 multi-byte sequences
    #   - Arrow keys (←→ cursor move, ↑↓ history navigation / scroll)
    #   - Alt+↑/↓  (scroll chat area)
    #   - Home / End
    #   - Backspace / Delete
    #   - Ctrl+A (beginning of line), Ctrl+E (end), Ctrl+U (clear), Ctrl+W (word delete)
    #   - Ctrl+C / Ctrl+D (interrupt / EOF)
    #   - Enter (submit)
    #   - Ctrl+L (redraw)
    #   - Ctrl+R (history search — future)
    #
    # Usage:
    #   handler = InputHandler.new
    #   event   = handler.read_event   # blocks until a keypress
    #   case event.type
    #   when :char   then buf.insert(cursor, event.char)
    #   when :enter  then submit(buf)
    #   when :ctrl_c then raise Interrupt
    #   ...
    #   end

    InputEvent = Data.define(:type, :char, :meta) do
      def self.new(type:, char: nil, meta: {})
        super(type: type, char: char, meta: meta.freeze)
      end
    end

    class InputHandler
      # Types emitted:
      #   :char          — printable character (see .char)
      #   :enter         — Enter / Return
      #   :backspace     — Backspace
      #   :delete        — Delete (forward delete)
      #   :arrow_left    — ←
      #   :arrow_right   — →
      #   :arrow_up      — ↑  (meta: { alt: true } for Alt+↑)
      #   :arrow_down    — ↓  (meta: { alt: true } for Alt+↓)
      #   :home          — Home
      #   :end_key       — End
      #   :ctrl_a        — Ctrl+A
      #   :ctrl_e        — Ctrl+E
      #   :ctrl_u        — Ctrl+U
      #   :ctrl_w        — Ctrl+W
      #   :ctrl_c        — Ctrl+C
      #   :ctrl_d        — Ctrl+D
      #   :ctrl_l        — Ctrl+L (redraw)
      #   :tab           — Tab (command completion)
      #   :escape        — bare Escape
      #   :resize        — terminal resize (SIGWINCH)
      #   :unknown       — unrecognised escape sequence

      def initialize(input = $stdin)
        @input  = input
        @resize = false
        # Catch SIGWINCH on Unix
        Signal.trap("WINCH") { @resize = true } rescue nil
      end

      # Block until one logical keypress is available, return InputEvent.
      def read_event
        # Drain any pending resize signal first
        if @resize
          @resize = false
          return InputEvent.new(type: :resize)
        end

        raw_read
      end

      private

      def raw_read
        @input.raw do |io|
          byte = io.getc
          return InputEvent.new(type: :ctrl_d) if byte.nil?   # EOF

          case byte
          when "\r", "\n"
            InputEvent.new(type: :enter)

          when "\x7F", "\b"
            InputEvent.new(type: :backspace)

          when "\x01"  then InputEvent.new(type: :ctrl_a)
          when "\x05"  then InputEvent.new(type: :ctrl_e)
          when "\x0B"  then InputEvent.new(type: :ctrl_k)
          when "\x15"  then InputEvent.new(type: :ctrl_u)
          when "\x17"  then InputEvent.new(type: :ctrl_w)
          when "\x03"  then InputEvent.new(type: :ctrl_c)
          when "\x04"  then InputEvent.new(type: :ctrl_d)
          when "\x0C"  then InputEvent.new(type: :ctrl_l)
          when "\t"    then InputEvent.new(type: :tab)

          when "\e"
            # Escape sequence — peek ahead with a short timeout
            parse_escape_sequence(io)

          else
            # Regular character (may be start of UTF-8 multi-byte)
            char = read_utf8(io, byte)
            char.match?(/[[:print:]]|\s/) ? InputEvent.new(type: :char, char: char) : InputEvent.new(type: :unknown)
          end
        end
      end

      # Parse what comes after an initial ESC byte.
      def parse_escape_sequence(io)
        # Check if more bytes follow within 50ms
        return InputEvent.new(type: :escape) unless io.wait_readable(0.05)

        next1 = io.getc
        return InputEvent.new(type: :escape) if next1.nil?

        case next1
        when "["
          # CSI sequence: ESC [ ...
          parse_csi(io)

        when "O"
          # SS3 sequence: ESC O A/B/C/D (arrow keys on some terminals)
          return InputEvent.new(type: :unknown) unless io.wait_readable(0.05)

          ch = io.getc
          case ch
          when "A" then InputEvent.new(type: :arrow_up)
          when "B" then InputEvent.new(type: :arrow_down)
          when "C" then InputEvent.new(type: :arrow_right)
          when "D" then InputEvent.new(type: :arrow_left)
          when "H" then InputEvent.new(type: :home)
          when "F" then InputEvent.new(type: :end_key)
          else InputEvent.new(type: :unknown)
          end

        when "\e"
          # Double ESC — Alt+Escape or similar; just return escape
          InputEvent.new(type: :escape)

        else
          # Alt+key: ESC followed by a printable character
          InputEvent.new(type: :char, char: next1, meta: { alt: true })
        end
      end

      # Parse a CSI (Control Sequence Introducer) sequence: ESC [ params final
      def parse_csi(io)
        params = +""
        loop do
          return InputEvent.new(type: :unknown) unless io.wait_readable(0.1)

          ch = io.getc
          break if ch.nil?

          if ch.match?(/[0-9;:<=>?]/)
            params << ch
          else
            # Final byte
            return decode_csi(params, ch)
          end
        end
        InputEvent.new(type: :unknown)
      end

      def decode_csi(params, final)
        case final
        when "A"
          # Up arrow — ESC [ A  or  ESC [ 1;3A (Alt+Up)
          alt = params.include?("3") || params.include?("9")
          InputEvent.new(type: :arrow_up, meta: { alt: alt })
        when "B"
          alt = params.include?("3") || params.include?("9")
          InputEvent.new(type: :arrow_down, meta: { alt: alt })
        when "C"
          InputEvent.new(type: :arrow_right)
        when "D"
          InputEvent.new(type: :arrow_left)
        when "H", "h"
          InputEvent.new(type: :home)
        when "F", "f"
          InputEvent.new(type: :end_key)
        when "~"
          case params
          when "1", "7" then InputEvent.new(type: :home)
          when "4", "8" then InputEvent.new(type: :end_key)
          when "3"      then InputEvent.new(type: :delete)
          else InputEvent.new(type: :unknown)
          end
        else
          InputEvent.new(type: :unknown)
        end
      end

      # Read a complete UTF-8 character starting with `first_byte`.
      # UTF-8 encoding:
      #   0xxxxxxx              — 1 byte  (ASCII)
      #   110xxxxx 10xxxxxx     — 2 bytes
      #   1110xxxx 10xxxxxx×2   — 3 bytes
      #   11110xxx 10xxxxxx×3   — 4 bytes
      def read_utf8(io, first_byte)
        b = first_byte.ord
        extra = if    b & 0b1111_1000 == 0b1111_0000 then 3
        elsif b & 0b1111_0000 == 0b1110_0000 then 2
        elsif b & 0b1110_0000 == 0b1100_0000 then 1
        else 0
        end
        buf = first_byte.dup
        extra.times do
          break unless io.wait_readable(0.05)

          c = io.getc
          break if c.nil?

          buf << c
        end
        buf.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
      end
    end

    # ---------------------------------------------------------------------------
    # LineEditor — manages a text buffer with cursor position
    # Handles all editing events produced by InputHandler.
    # ---------------------------------------------------------------------------
    class LineEditor
      attr_reader :buffer, :cursor, :history_index

      def initialize(history: [])
        @buffer        = +""
        @cursor        = 0
        @history       = history.dup
        @history_index = nil
        @saved_buffer  = nil
      end

      # Apply an InputEvent to the buffer. Returns :submit if Enter pressed.
      def handle(event) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength
        case event.type
        when :char
          insert(event.char)
        when :enter
          return :submit
        when :backspace
          delete_backward
        when :delete
          delete_forward
        when :arrow_left
          move_left
        when :arrow_right
          move_right
        when :home, :ctrl_a
          @cursor = 0
        when :end_key, :ctrl_e
          @cursor = @buffer.length
        when :ctrl_u
          @buffer = @buffer[@cursor..] || ""
          @cursor = 0
        when :ctrl_k
          @buffer = @buffer[0, @cursor] || ""
        when :ctrl_w
          delete_word_backward
        when :arrow_up
          history_prev
        when :arrow_down
          history_next
        end
        nil
      end

      def submit!
        text = @buffer.dup
        @history << text unless text.strip.empty? || @history.last == text
        @history_index = nil
        @saved_buffer  = nil
        @buffer = +""
        @cursor = 0
        text
      end

      def value    = @buffer.dup
      def empty?   = @buffer.strip.empty?
      def length   = @buffer.length

      private

      def insert(char)
        @buffer.insert(@cursor, char)
        @cursor += char.length
      end

      def delete_backward
        return if @cursor.zero?

        @cursor -= 1
        @buffer.slice!(@cursor, 1)
      end

      def delete_forward
        @buffer.slice!(@cursor, 1) if @cursor < @buffer.length
      end

      def move_left
        @cursor = [ @cursor - 1, 0 ].max
      end

      def move_right
        @cursor = [ @cursor + 1, @buffer.length ].min
      end

      def delete_word_backward
        return if @cursor.zero?

        # Skip trailing spaces, then delete word
        i = @cursor - 1
        i -= 1 while i > 0 && @buffer[i] == " "
        i -= 1 while i > 0 && @buffer[i] != " "
        i += 1 if @buffer[i] == " " && i > 0
        deleted = @cursor - i
        @buffer.slice!(i, deleted)
        @cursor = i
      end

      def history_prev
        return if @history.empty?

        if @history_index.nil?
          @saved_buffer  = @buffer.dup
          @history_index = @history.length - 1
        elsif @history_index > 0
          @history_index -= 1
        end
        @buffer = @history[@history_index].dup
        @cursor = @buffer.length
      end

      def history_next
        return if @history_index.nil?

        if @history_index < @history.length - 1
          @history_index += 1
          @buffer = @history[@history_index].dup
        else
          @history_index = nil
          @buffer = @saved_buffer.dup
          @saved_buffer = nil
        end
        @cursor = @buffer.length
      end
    end
  end
end
