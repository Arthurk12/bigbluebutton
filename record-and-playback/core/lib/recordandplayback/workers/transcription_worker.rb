module BigBlueButton
  module Resque
    class TranscriptionWorker < BaseWorker
      @queue = 'rap:transcription'

      def perform
        super do
          @logger.info("Running transcription worker for #{@full_id}")

          ret = nil
          if ENV["MCONF_REC_WORKER_LOG_STDOUT"] == "1"
            ret = BigBlueButton.exec_ret("bundle", "exec", "--gemfile=transcribe/Gemfile", "ruby", "transcribe/transcribe.rb", "-m", "#{@meeting_id}", "--log-stdout")
          else
            ret = BigBlueButton.exec_ret("bundle", "exec", "--gemfile=transcribe/Gemfile", "ruby", "transcribe/transcribe.rb", "-m", "#{@meeting_id}")
          end

          if ret.zero?
            @logger.info("Transcription succeeded for #{@full_id}")
          else
            @logger.error("Transcription failed for #{@full_id} (got #{ret})")
          end

          ret
        end
      end

      def initialize(opts)
        super(opts)
        @step_name = 'transcription'
      end
    end
  end
end
