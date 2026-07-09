FROM diegosouzapw/omniroute:latest

# Set production defaults
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV NODE_ENV=production
ENV DATA_DIR=/app/data

# Install backup and networking dependencies inside container
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates python3 python3-pip coreutils socat \
 && rm -rf /var/lib/apt/lists/*

# Install Hugging Face synchronization toolchains
RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages

WORKDIR /app

# Copy the background launcher file
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 20128

CMD ["/app/entrypoint.sh"]
