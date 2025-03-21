#!/bin/bash -e

yq d -i presentation.yml "video_formats[*]"
yq w -i presentation.yml "video_formats[0]" "${MCONF_REC_WORKER_VIDEO_FORMAT}"
yq w -i presentation.yml "video_output_width" "${MCONF_REC_WORKER_PRESENTATION_VIDEO_OUTPUT_WIDTH}"
yq w -i presentation.yml "video_output_height" "${MCONF_REC_WORKER_PRESENTATION_VIDEO_OUTPUT_HEIGHT}"
yq w -i presentation.yml "video_output_framerate" "${MCONF_REC_WORKER_PRESENTATION_VIDEO_OUTPUT_FRAMERATE}"

yq w -i bigbluebutton.yml "playback_host" "${MCONF_REC_WORKER_PLAYBACK_HOST}"
yq w -i bigbluebutton.yml "playback_protocol" "${MCONF_REC_WORKER_PLAYBACK_PROTOCOL}"
yq w -i bigbluebutton.yml "redis_host" "${MCONF_REC_NOTIFIER_REDIS_HOST}"
yq w -i bigbluebutton.yml "redis_port" "${MCONF_REC_NOTIFIER_REDIS_PORT}"
yq w -i bigbluebutton.yml "redis_password" "${MCONF_REC_NOTIFIER_REDIS_PASSWORD}"
yq w -i bigbluebutton.yml "redis_ssl" "${MCONF_REC_NOTIFIER_REDIS_SSL}"

yq w -i bigbluebutton.yml "notes_endpoint" "${MCONF_REC_ETHERPAD_ENDPOINT}"
yq w -i bigbluebutton.yml "notes_apikey" "${MCONF_REC_ETHERPAD_APIKEY}"

if [ "${MCONF_REC_CUSTOM_BIGBLUEBUTTON_YML}" != "" ]; then
  echo -e "${MCONF_REC_CUSTOM_BIGBLUEBUTTON_YML}" | tee -a bigbluebutton.yml
fi

if [ "${MCONF_REC_CUSTOM_VIDEO_YML}" != "" ]; then
  echo -e "${MCONF_REC_CUSTOM_VIDEO_YML}" | tee -a video.yml
fi

exec "$@"
