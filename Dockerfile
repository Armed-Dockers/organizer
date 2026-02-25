FROM python:3.11-alpine

# Install required packages
RUN apk add --no-cache \
    p7zip \
    inotify-tools \
    util-linux

# Copy unrar binary from linuxserver image
COPY --from=linuxserver/unrar:latest /usr/bin/unrar-alpine /usr/local/bin/unrar

# Install organize
RUN pip install --no-cache-dir organize-tool

WORKDIR /app

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default environment
ENV DOWNLOADS=/downloads
ENV ORGANIZE_CONFIG=/config/config.yaml
ENV LOG_FILE=/logs/organize.log
ENV DEBOUNCE_SECONDS=15

ENTRYPOINT ["/entrypoint.sh"]
