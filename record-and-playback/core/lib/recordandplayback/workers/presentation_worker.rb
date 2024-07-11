require File.expand_path('../../../../lib/rec_builder', __FILE__)

module BigBlueButton
  module Resque
    class PresentationWorker < BaseWorker
      @queue = 'rap:presentation'

      def perform
        super do
          @logger.info("Running presentation worker for #{@full_id}")

          builder = RecordingBuilder.new
          success = builder.perform(@meeting_id)
          ret = success ? 0 : 1

          if ret.zero?
            @logger.info("Presentation succeeded for #{@full_id}")
          else
            @logger.error("Presentation failed for #{@full_id} (got #{ret})")
          end

          ret
        end
      end

      def initialize(opts)
        super(opts)
        @step_name = 'presentation'
      end
    end
  end
end
