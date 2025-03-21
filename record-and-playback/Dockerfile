#
# Build with:
# docker build -t mconf/mconf-rec-worker:dev .
#
# Run with:
# docker run --rm -it --name rap --env-file .env.local -v $(pwd)/../raw:/var/bigbluebutton/recording/raw -v /tmp/published:/var/bigbluebutton/published mconf/mconf-rec-worker:dev bundle exec ruby docker-utils/single-job.rb --key 55d2606c67dff2a061825ea7410cd362130b2b27-1629108217077
#
# Upload raw to S3 with:
# docker run --rm -it -e BBB_S3_KEY=XXX -e BBB_S3_SECRET=XXX -e BBB_S3_REGION=us-east-1 -e BBB_S3_BUCKET=897506051177-mconf-uploads-temp-hml -v /var/bigbluebutton/recording/raw:/var/bigbluebutton/recording/raw mconf/mconf-rec-worker:dev ruby upload-raw-s3.rb -m 7cc5a7fbea42f1f8d016f3359f071a0b0630dcf0-1611190746326
#

FROM ubuntu:focal AS mp4-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBFULLNAME="mconf-rec"
ENV DEBEMAIL="felipe@mconf.com"
ENV UBUNTU_CODENAME=jammy
ENV UBUNTU_VERSION=22.04
# https://github.com/bigbluebutton/bbb-presentation-video/tags
ENV VERSION=5.0.0-beta.2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install --no-install-recommends -y software-properties-common \
 && add-apt-repository -y ppa:git-core/ppa \
 && apt-get install --no-install-recommends -y debhelper devscripts equivs git git-buildpackage pristine-tar \
 && git clone https://github.com/bigbluebutton/bbb-presentation-video source \
 && cd source \
 && git fetch --tags \
 && git checkout ${VERSION} \
 && eval "$(./dch_version.sh)" \
 && dch --newversion "${DCH_VERSION}" --force-bad-version --distribution "${UBUNTU_CODENAME}" "Automatic Build" \
 && rm -r .github \
 && mk-build-deps -i -r -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' \
 && gbp buildpackage --git-ignore-new --git-ignore-branch --no-sign

FROM mconf/mconf-rec:proxy-s3-noauth-0.3.7-889fa1d AS mconf-rec

FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=mp4-builder /bbb-presentation-video*.deb /tmp/bbb-presentation-video/

RUN apt-get update \
 && apt-get install --no-install-recommends -y \
  build-essential \
  curl \
  dbus-x11 \
  ffmpeg \
  git-core \
  gnupg2 \
  gnuplot \
  imagemagick \
  libcurl4-openssl-dev \
  libdbus-glib-1-2 \
  libgtk-3-0 \
  liblzma-dev \
  libncurses5-dev \
  libxml2-dev \
  libxslt1-dev \
  libyaml-dev \
  locales \
  mencoder \
  nginx \
  patch \
  poppler-utils \
  python3 \
  python3-dev \
  python3-icu \
  python3-lxml \
  python3-matplotlib \
  python3-pip \
  python3-setuptools \
  ruby-dev \
  sox \
  vorbis-tools \
  wget \
  xdotool \
  xvfb \
  zlib1g-dev \
# needed by gen_poll_svg
  gir1.2-pango-1.0 \
  python3-attr \
  python3-cairo \
  python3-gi \
  python3-gi-cairo \
# needed by monitor.py
  python3-cpuinfo \
  python3-matplotlib \
  python3-psutil \
# needed by journald-logger
  libsystemd-dev \
# needed by bbb-presentation-video
  fonts-croscore \
  gir1.2-gdkpixbuf-2.0 \
  gir1.2-gtk-3.0 \
  gir1.2-poppler-0.18 \
  python3-packaging \
  python3-sortedcollections \
# needed to generate svg
  cairosvg \
  libmagickcore-6.q16-6-extra \
  librsvg2-common \
  potrace \
  python3-cairosvg \
# Set the locale
 && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
 && locale-gen \
 && gem install bundler --version 2.3.23 \
 && curl -fsSL "https://ubuntu.bigbluebutton.org/repo/bigbluebutton.asc" | tee /etc/apt/keyrings/bigbluebutton.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/bigbluebutton.asc] https://ubuntu.bigbluebutton.org/jammy-300 bigbluebutton-jammy main" > /etc/apt/sources.list.d/bigbluebutton.list \
 && apt-get update \
 && apt-get install --no-install-recommends -y bbb-mkclean \
 && wget --quiet https://github.com/mikefarah/yq/releases/download/3.3.2/yq_linux_amd64 -O /usr/local/bin/yq \
 && chmod +x /usr/local/bin/yq \
 && wget http://ftp.us.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8.1_all.deb \
 && dpkg -i ttf-mscorefonts-installer_*.deb || true \
 && rm -v ttf-mscorefonts-installer_*.deb \
 && wget --quiet https://github.com/bigbluebutton/perfect-freehand-python/releases/download/1.2.0/python3-perfect-freehand_1.2.0_all.deb -P /tmp/bbb-presentation-video/ \
 && dpkg -i /tmp/bbb-presentation-video/*.deb || true \
 && rm -rv /tmp/bbb-presentation-video \
 && apt-get -f --no-install-recommends -y install \
 && fc-cache -f \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p ~/.fonts \
 && wget --quiet -O ~/.fonts/NotoColorEmoji.ttf https://github.com/googlefonts/noto-emoji/blob/main/fonts/NotoColorEmoji.ttf?raw=true \
 && fc-cache -f -v

WORKDIR /usr/local/bigbluebutton/core

COPY Gemfile Gemfile.lock ./
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1 \
 && bundle install \
 && mkdir -p /var/bigbluebutton/playback/presentation \
             /var/bigbluebutton/published/presentation  \
             /var/bigbluebutton/published/video \
             /var/bigbluebutton/published/podcast \
             /var/bigbluebutton/recording/process \
             /var/bigbluebutton/recording/publish \
             /var/bigbluebutton/recording/status/ended \
             /var/bigbluebutton/recording/status/recorded \
             /var/bigbluebutton/recording/status/archived \
             /var/bigbluebutton/recording/status/sanity \
             /var/bigbluebutton/recording/status/processed \
             /var/bigbluebutton/recording/status/published \
             /var/log/bigbluebutton/presentation \
             /var/log/bigbluebutton/video \
             /var/log/bigbluebutton/podcast \
             /var/bigbluebutton/events \
             /var/bigbluebutton/mconf-data

COPY --from=mconf-rec /var/bigbluebutton/playback/elos/playback/presentation/2.3 /var/bigbluebutton/playback/presentation/2.3

WORKDIR /usr/local/bigbluebutton/core

COPY ./core/scripts/transcribe/Gemfile* ./scripts/transcribe/

WORKDIR /usr/local/bigbluebutton/core/scripts/transcribe

RUN bundle install

WORKDIR /usr/local/bigbluebutton/core

COPY ./core/Rakefile ./
COPY ./core/lib ./lib/
COPY ./core/scripts ./scripts/
COPY ./core/scripts/transcribe/transcribe_gladia.rb ./scripts/transcribe/transcribe.rb

WORKDIR /usr/local/bigbluebutton/core/scripts

COPY ./presentation/scripts/presentation.yml ./
COPY ./presentation/scripts/process/ ./process/
COPY ./presentation/scripts/publish/ ./publish/
COPY ./presentation/playback/ /var/bigbluebutton/playback/

COPY ./video/scripts/video.yml ./
COPY ./video/scripts/process/ ./process/
COPY ./video/scripts/publish/ ./publish/
COPY ./video/playback/ /usr/local/bigbluebutton/core/playback/

COPY ./podcast/scripts/podcast.yml ./
COPY ./podcast/scripts/process/ ./process/
COPY ./podcast/scripts/publish/ ./publish/

COPY ./mconf_decrypter/scripts/ .

COPY ./docker-utils/docker-entrypoint.sh /usr/local/bin/

ENV MCONF_REC_WORKER_VIDEO_FORMAT="mp4"
ENV MCONF_REC_WORKER_PLAYBACK_HOST="127.0.0.1"
ENV MCONF_REC_WORKER_PLAYBACK_PROTOCOL="http"

ENV MCONF_REC_WORKER_PRESENTATION_VIDEO_OUTPUT_WIDTH=640
ENV MCONF_REC_WORKER_PRESENTATION_VIDEO_OUTPUT_HEIGHT=480
ENV MCONF_REC_WORKER_PRESENTATION_VIDEO_OUTPUT_FRAMERATE=15

ENV MCONF_REC_WORKER_LOOP=0
ENV MCONF_REC_WORKER_LOOP_WAIT=60
ENV MCONF_REC_WORKER_POLLING_WAIT=20
ENV MCONF_REC_WORKER_LOCALE="pt-BR"
ENV MCONF_REC_WORKER_FORMAT="presentation,video,podcast"
ENV MCONF_REC_WORKER_RECORD_ID=""
ENV MCONF_REC_WORKER_LOG_STDOUT=1

ENV MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_ACCESS_KEY_ID=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_SECRET_ACCESS_KEY=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_ENDPOINT=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_REGION=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_NAME=""

ENV MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_ACCESS_KEY_ID=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_SECRET_ACCESS_KEY=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_ENDPOINT=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_REGION=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_NOTIFY_NAME=""

ENV MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_ACCESS_KEY_ID=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_SECRET_ACCESS_KEY=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_ENDPOINT=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_REGION=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_NAME=""

ENV MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_ACCESS_KEY_ID=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_SECRET_ACCESS_KEY=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_ENDPOINT=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_REGION=""
ENV MCONF_REC_WORKER_AWS_S3_BUCKET_STATS_NAME=""

ENV MCONF_REC_WORKER_AWS_S3_TAGGING_SUPPORTED="true"

ENV MCONF_REC_WORKER_FORMAT_PRESENTATION_ENABLED="true"
ENV MCONF_REC_WORKER_FORMAT_VIDEO_ENABLED="true"
ENV MCONF_REC_WORKER_FORMAT_PODCAST_ENABLED="false"

ENV MCONF_REC_WORKER_TRANSCRIBE_ENABLED="false"
ENV MCONF_REC_CUSTOM_TRANSCRIBE_YML_B64=""

ENV MCONF_REC_NOTIFIER_REDIS_ENABLED=0
ENV MCONF_REC_NOTIFIER_REDIS_HOST="localhost"
ENV MCONF_REC_NOTIFIER_REDIS_PORT="6379"
ENV MCONF_REC_NOTIFIER_REDIS_PASSWORD=""
ENV MCONF_REC_NOTIFIER_REDIS_SSL=false

ENV MCONF_REC_NOTIFIER_WEBHOOK_ENABLED=0
ENV MCONF_REC_NOTIFIER_WEBHOOK_URI=""
ENV MCONF_REC_NOTIFIER_WEBHOOK_BEARER_AUTH=""
ENV MCONF_REC_NOTIFIER_WEBHOOK_DOMAIN=""

ENV MCONF_REC_NOTIFIER_ELASTIC_ENABLED=0
ENV MCONF_REC_NOTIFIER_ELASTIC_HOST=""
ENV MCONF_REC_NOTIFIER_ELASTIC_PATH=""
ENV MCONF_REC_NOTIFIER_ELASTIC_PORT=""
ENV MCONF_REC_NOTIFIER_ELASTIC_AUTH_USER=""
ENV MCONF_REC_NOTIFIER_ELASTIC_AUTH_PASS=""
ENV MCONF_REC_NOTIFIER_ELASTIC_SCHEME=""
# use summary-* or summary-meeting-*
ENV MCONF_REC_NOTIFIER_ELASTIC_INDEX="summary-*"

ENV MCONF_REC_ETHERPAD_ENDPOINT="http://127.0.0.1:9001"
ENV MCONF_REC_ETHERPAD_APIKEY="ETHERPAD_APIKEY"

ENV MCONF_REC_CUSTOM_BIGBLUEBUTTON_YML=""

ENV COUNT=1
ENV QUEUE=*
ENV TERM_CHILD=1

ENTRYPOINT [ "/usr/local/bin/docker-entrypoint.sh" ]
CMD ["bundle", "exec", "ruby", "docker-utils/resque-wait-archived.rb"]
