# frozen_string_literal: true

require 'rake'
require 'stringio'

module RakeTaskHelpers
  def run_task(name, *)
    capture_output { Rake::Task[name].invoke(*) }
  end

  # Slience stdout and stderr so a task's messages don't leak into test output
  def capture_output
    original_out = $stdout
    original_err = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_out
    $stderr = original_err
  end
end

# Load task definitions here because specs don't have the rake command to do it
RSpec.configure do |config|
  config.before(:suite) do
    Rake.application = Rake::Application.new
    Rake.application.init('rake', []) # Explicitly pass an empty ARGV
    Rake.application.load_rakefile
  end

  # The test suite is one Rake process running many examples, but Rake marks a
  # task as invoked after it runs and won't run it again until re-enabled
  config.before do
    Rake.application.tasks.each(&:reenable)
  end

  config.include RakeTaskHelpers, type: :task
end
