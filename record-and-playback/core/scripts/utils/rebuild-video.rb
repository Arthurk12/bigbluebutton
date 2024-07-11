# Set encoding to utf-8
# encoding: UTF-8

#
# Run with:
# ID=14fdc913a14f6083605aba09311725c31126074f-1606219074810
# docker run --rm -d --name rap-${ID} -v /dados/bigbluebutton/published/presentation:/var/bigbluebutton/published/presentation:ro -v $(pwd)/${ID}:/var/bigbluebutton/published/presentation_video mconf/mconf-rec-worker:latest ruby utils/rebuild-video.rb -m ${ID}
#

require 'optimist'

require File.expand_path('../../../lib/rec_builder', __FILE__)

opts = Optimist::options do
  opt :meeting_id, "RecordID to upload", :type => String, :required => true
end
meeting_id = opts[:meeting_id]

builder = RecordingBuilder.new(skip_presentation: true, skip_presentation_video: false, skip_push_to_s3: true, rebuild: false)
builder.perform(meeting_id)
