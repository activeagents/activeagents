# frozen_string_literal: true

module CodeHelper
  def highlight_ruby(code)
    formatter = Rouge::Formatters::HTML.new
    lexer = Rouge::Lexers::Ruby.new
    formatter.format(lexer.lex(code.strip)).html_safe
  end
end
