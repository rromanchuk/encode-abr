#!/bin/bash
set -e

while getopts "k:b:r:" opt
do
   case "$opt" in
      k ) KEY="$OPTARG" ;;
      b ) BUCKET="$OPTARG" ;;
      r ) REPORT="true" ;;
      ? ) helpFunction ;;
   esac
done


printf "Running.... $0 -s $KEY -b $BUCKET\n"

PREFIX=${KEY%%.*}
HLS_OUTPUTS=/tmp/$PREFIX/out
FILE_OUTPUTS=/tmp/$PREFIX
mkdir -p $HLS_OUTPUTS


cd /tmp/$PREFIX
printf "\nWhere are we?\n"
pwd
printf "\nWhats here?\n"
ls -lah


printf "\n\n\nStarting ABR generation...\nFirst checking if the video has an audio stream..."
# HEVC bitrate guidance https://www.streamingmedia.com/Articles/ReadArticle.aspx?ArticleID=121878


# Insane hack to detect timelapse videos missing an audio track in order to branch ffmpeg stream map.
# Hls generation doesn't support an optional -map '0:a:0'? so the command will fail
HAS_AUDIO=`ffprobe -i $KEY -show_streams -select_streams a -loglevel error`

if [ -z "$HAS_AUDIO" ]
then
  printf "\n\n Missing audio stream!\n Running modified ffmpeg command."
  ffmpeg -hide_banner -y -i $KEY \
    -filter_complex "[0:v:0]split=3[SPLIT_1][SPLIT_2][SPLIT_3] ; [SPLIT_1]scale=width='min(540,iw)':height=-2[VIDEO_HEVC_720] ; [SPLIT_2]scale=width=432:height=-2[VIDEO_HEVC_432] ; [SPLIT_3]scale=width=234:height=-2[VIDEO_AVC_234]" \
    -preset 'veryfast' -pix_fmt:v 'yuv420p' \
    -flags +cgop -g 60 -x265-params:v bframes=0:keyint=60:min-keyint=60  \
    -map '[VIDEO_HEVC_720]' -codec:v:0 'libx265' -forced-idr:v:0 1 -tag:v:0 hvc1 -crf:v:0 30 -maxrate:v:0 440k -bufsize:v:0 880k  \
    -map '[VIDEO_HEVC_432]' -codec:v:1 'libx265' -forced-idr:v:1 1 -tag:v:1 hvc1 -crf:v:1 30 -maxrate:v:1 220k -bufsize:v:1 440k  \
    -map '[VIDEO_AVC_234]' -keyint_min:v:2 60 -codec:v:2 'libx264' -crf:v:2 23 -maxrate:v:2 150k -bufsize:v:2 250k \
    -f "hls" -hls_time 6 -hls_segment_type 'fmp4' -hls_flags '+single_file' -hls_playlist_type 'vod' -var_stream_map "v:0,name:HEVC720 v:1,name:HEVC432 v:2,name:AVC234" \
    -master_pl_name 'master.m3u8' \
    -hls_segment_filename 'out/%v.mp4' 'out/%v.m3u8'
else
  ffmpeg -hide_banner -y -i $KEY \
    -filter_complex "[0:v:0]split=3[SPLIT_1][SPLIT_2][SPLIT_3] ; [SPLIT_1]scale=width='min(540,iw)':height=-2[VIDEO_HEVC_720] ; [SPLIT_2]scale=width=432:height=-2[VIDEO_HEVC_432] ; [SPLIT_3]scale=width=234:height=-2[VIDEO_AVC_234]" \
    -preset 'veryfast' -pix_fmt:v 'yuv420p' \
    -flags +cgop -g 60 -x265-params:v bframes=0:keyint=60:min-keyint=60  \
    -map '[VIDEO_HEVC_720]' -codec:v:0 'libx265' -forced-idr:v:0 1 -tag:v:0 hvc1 -crf:v:0 30 -maxrate:v:0 440k -bufsize:v:0 880k  \
    -map '[VIDEO_HEVC_432]' -codec:v:1 'libx265' -forced-idr:v:1 1 -tag:v:1 hvc1 -crf:v:1 30 -maxrate:v:1 220k -bufsize:v:1 440k  \
    -map '[VIDEO_AVC_234]' -keyint_min:v:2 60 -codec:v:2 'libx264' -crf:v:2 23 -maxrate:v:2 150k -bufsize:v:2 250k \
    -map '0:a:0' -codec:a copy \
    -f "hls" -hls_time 6 -hls_segment_type 'fmp4' -hls_flags '+single_file' -hls_playlist_type 'vod' -var_stream_map "a:0,name:AUDIO,agroup:common_audio,default:YES,language:ENG v:0,name:HEVC720,agroup:common_audio v:1,name:HEVC432,agroup:common_audio v:2,name:AVC234,agroup:common_audio" \
    -master_pl_name 'master.m3u8' \
    -hls_segment_filename 'out/%v.mp4' 'out/%v.m3u8'
fi

# If using a CDN, gzip m3u8 playlists and remove the .gz extension. Content-Encoding *must* be set to gz.
# According to cloudfront docs, application/vnd.apple.mpegurl, application/x-mpegurl content-types support
# on the fly compression from the origin.
# see https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/ServingCompressedFiles.html#compressed-content-cloudfront-file-types
# find ./out -type f -name "*.m3u8" | xargs -P 8 -I {} \
#     bash -c '! gunzip -t $1 2>/dev/null && gzip -v $1 && mv -v $1.gz $1;' _ {} \;

printf "\n\n\nFinished ABR generation"


ls -lah ./out
cat ./out/master.m3u8

printf "\n\n\nStarting thumbnail generation...\n"
# Thumbnail generation, take a frame at 1/2 duration of the source. Insane hack to protect edge case
# where UGC is sub second, one second durations
ffmpeg -hide_banner -y -ss `ffmpeg -i $KEY 2>&1 | grep Duration | awk '{print $2}' | tr -d , | awk -F ':' '{print ($3+$2*60+$1*3600)/2}'` -i $KEY -frames:v 1 -q:v 2 thumbnail.jpg

# Pass -r for debugging
if [ -n "$REPORT"	]
then
  mediastreamvalidator -d iphone output/master.m3u8
  hlsreport.py validation_data.json
  open .
  open validation_data.html
fi

if [ $? -eq 0 ]
then
  printf "\n\n\nSUCCESS\n\n\n"
  exit 0
else
  printf "\n\n\nFAILED\n\n\n" >&2
  exit 1
fi