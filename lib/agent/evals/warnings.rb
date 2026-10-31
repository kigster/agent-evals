# frozen_string_literal: true

require "logger"

module Agent
  module Evals
    # Everything a run would otherwise print as a warning while its progress
    # bars redraw: cases that failed, and what Braintrust, RubyLLM, OpenTelemetry
    # (whose exporters report failures on $stdout) and Ruby itself log. Printed among the bars, each one breaks the redraw; collected
    # here, they are saved to one file, and the run prints only how many.
    #
    # It quacks as an IO, so a Logger, and $stderr, can write to it. Threads
    # share it.
    class Warnings
      def initialize
        @lines = []
        @lock = Mutex.new
      end

      # @param text [#to_s]
      # @return [self]
      def record(text)
        text = text.to_s.chomp
        @lock.synchronize { @lines << text } unless text.strip.empty?
        self
      end

      # @return [Integer] the bytes "written", as IO#write does
      def write(*texts)
        texts.each { record(it) }
        texts.sum { it.to_s.bytesize }
      end

      def puts(*texts) = texts.each { record(it) } && nil
      def print(*texts) = write(*texts) && nil
      def <<(text) = record(text)
      def flush = self
      def sync = true
      def sync=(_value); end
      def close = nil
      def tty? = false

      # @return [Integer]
      def count = @lock.synchronize { @lines.size }

      # @return [Array<String>]
      def to_a = @lock.synchronize { @lines.dup }

      # @return [Boolean] whether nothing was recorded
      def none? = count.zero?

      # @param path [String]
      # @return [String] the path
      def save(path)
        File.write(path, "#{to_a.join("\n\n")}\n")
        path
      end

      # Runs the block with $stderr, Ruby's own warnings, and the loggers of
      # whichever optional gems are loaded writing here, and puts them back after.
      #
      # @return [Object] what the block returns
      def capture
        logger = Logger.new(self, level: Logger::WARN)
        stderr = $stderr
        restore = redirect_loggers(logger)
        $stderr = self
        yield
      ensure
        restore&.call
        $stderr = stderr
      end

      private

      # @return [Proc] puts the loggers back
      def redirect_loggers(logger)
        braintrust = defined?(Braintrust::Log) ? Braintrust::Log.logger : nil
        ruby_llm = defined?(RubyLLM) ? RubyLLM.instance_variable_get(:@logger) : nil
        open_telemetry = defined?(OpenTelemetry) ? OpenTelemetry.logger : nil
        Braintrust::Log.logger = logger if defined?(Braintrust::Log)
        RubyLLM.instance_variable_set(:@logger, logger) if defined?(RubyLLM)
        OpenTelemetry.logger = logger if defined?(OpenTelemetry)
        lambda do
          Braintrust::Log.logger = braintrust if defined?(Braintrust::Log)
          RubyLLM.instance_variable_set(:@logger, ruby_llm) if defined?(RubyLLM)
          OpenTelemetry.logger = open_telemetry if defined?(OpenTelemetry)
        end
      end
    end
  end
end
