# require 'httparty'
require 'json'
require 'logger'
require 'aws-sdk-s3'
require 'aws-sdk-sns'
require 'amazing_print'
require 'open3'

DEST_BUCKET = ENV['DEST_BUCKET']

def lambda_handler(event:, context:)
  logger = Logger.new($stdout)

  ap event

  records = event['Records'].map do |record|
    body = JSON.parse(record['body'])
    ap body
    { video: Aws::S3::Object.new(bucket_name: body['bucket'], key: body['key']), message_id: record['messageId'], sns_topic: body['sns_topic'] }
  end
  ap records

  failed_records = []

  records.each do |record|
    prefix = SecureRandom.uuid
    video = record[:video]
    puts "Downloading input source"
    video.download_file(new_source_path(prefix))
    stdout_str, error_str, status = Open3.capture3("./encode.sh -k #{prefix}.mp4 -b #{video.bucket_name}")
    logger.info(`ls -lah /tmp`)
    puts stdout_str
    puts error_str
    ap status

    if status.success?
      puts "ENCODING SUCCESS"
      upload(prefix)
      publish_outcome(prefix: prefix, record: record, outcome: :success)
    else
      puts "ENCODING FAILED"
      failed_records << record
      publish_outcome(prefix: prefix, record: record, outcome: :failure)
    end

    FileUtils.remove_dir(prefix_path(prefix))
  end



  {
    statusCode: 200,
    body: {
      batchItemFailures: failed_records.map do |record|
        { itemIdentifier: record[:message_id] }
      end
      # location: response.body
    }.to_json
  }
end

def video_hls_key(prefix)
  "vod/hevc/#{prefix}/master.m3u8"
end

def new_source_key(prefix)
  "vod/source/#{prefix}/original.mp4"
end

def new_source_path(prefix)

  `mkdir -p /tmp/#{prefix}/`
  "/tmp/#{prefix}/#{prefix}.mp4"
end

def video_thumbnail_key(prefix)
  "vod/thumbs/#{prefix}/thumbnail.jpg"
end

def video_thumbnail_path(prefix)
  "/tmp/#{prefix}/thumbnail.jpg"
end

def prefix_path(prefix)
  "/tmp/#{prefix}"
end



def upload(prefix)
  hls_objects = upload_hls(prefix)
  ap hls_objects

  new_src_video_obj = Aws::S3::Object.new(DEST_BUCKET, new_source_key(prefix))
  puts("Finished uploading #{new_src_video_obj.key}") if new_src_video_obj.upload_file(new_source_path(prefix), storage_class: 'INTELLIGENT_TIERING', cache_control: "max-age=31536000", content_type: 'video/mpeg')

  thumnail_obj = Aws::S3::Object.new(DEST_BUCKET, video_thumbnail_key(prefix))
  puts("Finished uploading #{thumnail_obj.key}") if thumnail_obj.upload_file(video_thumbnail_path(prefix), storage_class: 'INTELLIGENT_TIERING', cache_control: "max-age=31536000", content_type: 'image/jpeg')
end

def upload_hls(prefix)
  hls_prefix_key = "vod/hevc/#{prefix}/"
  hls_path_prefix = "/tmp/#{prefix}/out"
  hls_objects = []
  Dir.foreach(hls_path_prefix) do |filename|
    next if ['.', '..'].include?(filename)

    # Do work on the remaining files & directories
    content_type = case filename
    when /m3u/
      'application/vnd.apple.mpegurl'
    when /AUDIO/
      'audio/mp4'
    when /mp4/
      'video/mp4'
    end

    key = hls_prefix_key + filename
    hls_obj = Aws::S3::Object.new(DEST_BUCKET, key)
    puts "Uploading #{hls_path_prefix}/#{filename} to #{key}"
    hls_obj.upload_file("#{hls_path_prefix}/#{filename}", storage_class: 'INTELLIGENT_TIERING', cache_control: "max-age=31536000", content_type: content_type)
    hls_objects << hls_obj
  end
  hls_objects
end

def sns_payload(prefix)
  {
    stream_key: video_hls_key(prefix),
    thumbnail_key: video_thumbnail_key(prefix),
    file_key: new_source_key(prefix),
    output_bucket: DEST_BUCKET
  }.compact
end

def publish_outcome(prefix:, record:, outcome:)
  topic_arn = record[:sns_topic]
  video = record[:video]
  return unless topic_arn

  video_payload = sns_payload(prefix)
  ap video_payload

  Aws::SNS::Client.new(region: 'us-east-1').publish({ topic_arn: topic_arn, message: { outcome: outcome, key: video.key, video: video_payload }.to_json })
end
