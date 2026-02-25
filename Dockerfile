FROM python:3.11-alpine

# Install dependencies
RUN apk add --no-cache \
    inotify-tools \
    util-linux \
    p7zip \
    su-exec

# Copy unrar binary from LinuxServer image
COPY --from=linuxserver/unrar:latest /usr/bin/unrar-alpine /usr/local/bin/unrar

# Install organize
RUN pip install --no-cache-dir organize

# Copy scripts
COPY entrypoint.sh /entrypoint.sh
COPY organize-wrapper.sh /usr/local/bin/organize-wrapper.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/organize-wrapper.sh

ENTRYPOINT ["/entrypoint.sh"]
