require File.expand_path('../../../../lib/rec_builder', __FILE__)

module BigBlueButton
  module Resque
    class VideoWorker < BaseWorker
      @queue = 'rap:presentation_video'

      def perform
        super do
          @logger.info("Running presentation_video worker for #{@full_id}")

          builder = RecordingBuilder.new
          success = builder.perform(@meeting_id)
          ret = success ? 0 : 1

          if ret.zero?
            @logger.info("Presentation video succeeded for #{@full_id}")
          else
            @logger.error("Presentation video failed for #{@full_id} (got #{ret})")
          end

          ret
        end
      end

      def initialize(opts)
        super(opts)
        @step_name = 'video'
      end
    end
  end
end
