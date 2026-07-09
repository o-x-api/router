FROM node:20-slim

WORKDIR /app

# Install system dependencies (git for cloning, python3 and pip for sync wrapper)
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Hugging Face Hub library for our Python sync agent
RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages

# Clone the official OmniRoute repository directly into the workspace
RUN git clone https://github.com/diegosouzapw/OmniRoute.git .

# Install application dependencies and compile the distribution assets
RUN npm install
RUN npm run build

# Copy our sync wrapper script into the context environment
COPY entrypoint.py /app/entrypoint.py
RUN chmod +x /app/entrypoint.py

# Configure the system-wide storage variable targeted by OmniRoute
ENV OMNIROUT_DATA_DIR=/app/data
RUN mkdir -p /app/data

# Expose internal execution volume for runtime backups
VOLUME /app/data

# Direct traffic allocation to our wrapper entrypoint
ENTRYPOINT ["python3", "/app/entrypoint.py"]
