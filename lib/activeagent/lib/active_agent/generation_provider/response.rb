# frozen_string_literal: true

module ActiveAgent
  module GenerationProvider
    class Response
      attr_reader :response

      def initialize(response)
        @response = response
      end

      def content
        raise NotImplementedError, "Subclasses must implement the content method"
      end

      def function_call?
        false
      end

      def function_name
        nil
      end

      def function_arguments
        {}
      end
    end
  end
end
