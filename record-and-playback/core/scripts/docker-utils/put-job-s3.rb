# Set encoding to utf-8
# encoding: UTF-8

require 'dotenv'
require 'optimist'
require 'yaml'

require File.expand_path('../../../lib/recordandplayback', __FILE__)
require File.expand_path('../../../lib/bigbluebutton_s3', __FILE__)

Dotenv.load(
  File.join(File.dirname(__FILE__), '.env.local'),
  File.join(File.dirname(__FILE__), '.env')
)

key = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_ACCESS_KEY_ID'] || ""
secret = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_SECRET_ACCESS_KEY'] || ""
endpoint = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_ENDPOINT']
region = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_REGION']
bucket = ENV['MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_NAME']

opts = Optimist::options do
  opt :num, "Number of random recordings to upload", :type => :int
  opt :key, "Specific key to upload", :type => :string
end

s3_credentials = nil
unless key.empty? or secret.empty?
  s3_credentials = Aws::Credentials.new(key, secret)
end
s3_client = Aws::S3::Client.new(
  credentials: s3_credentials,
  region: region
)
s3 = Aws::S3::Resource.new(
  client: s3_client
)
publisher = BigBlueButtonS3::Publisher.new(client: s3_client)

list = []
if opts[:key]
  list << opts[:key]
else
  list = publisher.list_objects("raw/", bucket).reject{ |key| key.start_with?("raw/trigger/") }
  list = list.sample(opts[:num]) if opts[:num] > 0
end

temp_file = "/tmp/temp_s3.txt"
FileUtils.touch temp_file

list.each do |key|
  metadata = s3.bucket(bucket).object(key).metadata

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

  publisher.upload_dir(temp_file, temp_key, bucket, metadata: metadata)
end
