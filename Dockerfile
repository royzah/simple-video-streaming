FROM debian:bookworm-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        gstreamer1.0-tools \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav \
        gstreamer1.0-x \
        bash \
        iputils-ping \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY stream.sh view.sh /app/
RUN chmod +x /app/stream.sh /app/view.sh

ENV GST_DEBUG=1
CMD ["/bin/bash"]
