# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # Offline checks that every case agrees with what its suite demands of it.
      class Verify < Command
        desc "Check every case's input and expected answer, through the adapter and the scorer (no API calls)"

        def call(**)
          all = discovery.all
          failures = LLM::Evals::Verify.new(configuration).problems
          if failures.empty?
            status_box :success, "#{all.size} cases verified across #{discovery.datasets.join(", ")}"
            return
          end

          failures.each { |name, problems| problems.each { status_box :error, "#{name}: #{it}", stream: err } }
          raise Error, "#{failures.size} case(s) failed verification"
        end
      end
    end
  end
end
