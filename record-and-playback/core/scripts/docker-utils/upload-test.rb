# Set encoding to utf-8
# encoding: UTF-8

require 'optimist'
require 'yaml'

require File.expand_path('../../../lib/recordandplayback', __FILE__)
require File.expand_path('../../../lib/bigbluebutton_s3', __FILE__)

region = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_REGION']
bucket = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_NAME']

$stdout.sync = true
logger = Logger.new(STDOUT)

logger.info "Starting job using the following environment variables:\n#{ ENV.map{ |key, value| "  #{key}=#{value}" }.sort.join("\n") }"

Aws.config.update(
  logger: logger
)

opts = Optimist::options do
  opt :key, "Specific key to upload", :type => :string, :default => "sample.txt"
end

s3_credentials = nil
if isset("MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_ACCESS_KEY_ID") and isset("MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_SECRET_ACCESS_KEY")
  s3_credentials = Aws::Credentials.new(ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_ACCESS_KEY_ID'], ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_SECRET_ACCESS_KEY'])
end
s3_client = Aws::S3::Client.new(
  credentials: s3_credentials,
  region: region
)
s3 = Aws::S3::Resource.new(
  client: s3_client
)

BigBlueButtonS3::logger = logger
publisher = BigBlueButtonS3::Publisher.new(client: s3_client)

list = [ opts[:key] ]
temp_file = opts[:key]

list.each do |key|
  temp_key = "raw/trigger/#{File.basename(key)}"

  output = s3.bucket(bucket).delete_objects(
    {
      delete: {
        objects: [
          { key: temp_key }
        ]
      }
    }
  )

  publisher.upload_dir(temp_file, temp_key, bucket)
end
