# Set encoding to utf-8
# encoding: UTF-8

#
# Run with:
# docker run --rm -it --name rap --env-file .env.local -v $(pwd)/tmp/published_presentation:/var/bigbluebutton/published/presentation -v $(pwd)/tmp/published_presentation_video:/var/bigbluebutton/published/presentation_video -v $(pwd)/tmp/raw:/var/bigbluebutton/recording/raw mconf/mconf-rec-worker:dev ruby docker-utils/single-job.rb --key 90c29ecf353ae8b3353fe314566327f89cf6ccbd-1625663706504
# docker run --rm -it --name rap -v $(pwd)/published_presentation_video:/var/bigbluebutton/published/presentation_video mconf/mconf-rec-worker:1.0.8-ef85b99508 ruby docker-utils/single-job.rb --key "https://develop.bigbluebutton.org/playback/presentation/2.3/183f0bf3a0982a127bdb8161e0c44eb696b3e75c-1600110331094"
#

require 'cgi'
require 'logger'
require 'optimist'

require File.expand_path('../media-reporter', __FILE__)
require File.expand_path('../../../lib/rec_builder', __FILE__)

logger = Logger.new(STDOUT)

logger.info "Starting job using the following environment variables:\n#{ ENV.map{ |key, value| "  #{key}=#{value}" }.sort.join("\n") }"

opts = Optimist::options do
  opt :key, "Specific key uploaded", :type => :string, :required => true
end

record_id = opts[:key].start_with?("http") ? opts[:key] : File.basename(CGI::unescape(opts[:key]), ".tar")

builder = RecordingBuilder.new
builder.logger = logger

FileUtils.mkdir_p "/stats"
monit_proc = BigBlueButton.execute_async('python3 docker-utils/monitor.py')
builder.perform(record_id)
BigBlueButton.kill(monit_proc)
BigBlueButton.wait(monit_proc, 300)

if BigBlueButton.isset('MCONF_REC_NOTIFIER_ELASTIC_MEDIA_STATS_INDEX')
  reporter = MediaReporter.new
  reporter.logger = logger
  reporter.perform(record_id)
end

s3_key = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_ACCESS_KEY_ID'] || ""
s3_secret = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_SECRET_ACCESS_KEY'] || ""
s3_endpoint = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_ENDPOINT']
s3_region = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_REGION']

opts = {
  :region => s3_region
}
unless s3_key.empty? or s3_secret.empty?
  opts[:credentials] = Aws::Credentials.new(s3_key, s3_secret)
end
s3_client = Aws::S3::Client.new(opts) rescue nil

if s3_client
  s3 = Aws::S3::Resource.new(
    client: s3_client
  )
  publisher = BigBlueButtonS3::Publisher.new(client: s3_client)

  if BigBlueButton.isset('MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_NAME') and format == 'presentation'
    bucket_notify = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_NAME']
    temp_file = "/tmp/temp_s3.txt"
    FileUtils.touch temp_file

    temp_key = "presentation_video/#{record_id}"
    output = s3.bucket(bucket_notify).delete_objects(
      {
        delete: {
          objects: [
            { key: temp_key }
          ]
        }
      }
    )

    publisher.upload_dir(temp_file, temp_key, bucket_notify)
  end

  # publisher is using credentials for NOTIFY
  if BigBlueButton.isset('MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_NAME')
    bucket_stats = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_NAME']
    [ "cpu.png", "memory.png" ].each do |f|
      stats_file = "/stats/#{f}"
      key = "stats/"
      key += "#{format}_" unless format.nil? or format.length == 0
      key += record_id
      key += "_#{ENV['AWS_BATCH_JOB_ID']}" unless ENV['AWS_BATCH_JOB_ID'].nil? or ENV['AWS_BATCH_JOB_ID'].length == 0
      key += "_#{ENV['AWS_BATCH_JOB_ATTEMPT']}" unless ENV['AWS_BATCH_JOB_ATTEMPT'].nil? or ENV['AWS_BATCH_JOB_ATTEMPT'].length == 0
      key += "_#{f}"

      publisher.upload_dir(stats_file, key, bucket_stats)
    end
  end
end
