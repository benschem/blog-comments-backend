# frozen_string_literal: true

# Silence AppLogger in test output
AppLogger.reopen(File::NULL)
