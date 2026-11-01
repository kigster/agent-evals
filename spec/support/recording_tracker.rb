# frozen_string_literal: true

# A tracker that remembers every callback, for specs that watch the run.
class RecordingTracker < LLM::Evals::Tracker
  def self.env_key = "RECORDING_TRACKER_KEY"

  attr_reader :events

  def initialize(url: nil, enabled: true, **context)
    super(**context)
    @url = url
    @enabled = enabled
    @events = []
  end

  def enabled? = @enabled
  def start(experiment) = @events << [:start, experiment]
  def record(result) = @events << [:record, result]

  def finish(_experiment, summary)
    @events << [:finish, summary]
    { url: @url }
  end
end
