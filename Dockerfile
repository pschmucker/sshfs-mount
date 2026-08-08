FROM alpine:3.24.1

# Install SSHFS and dependencies
RUN apk add --no-cache \
    sshfs \
    openssh-client \
    bash \
    ca-certificates

# Create mount point
RUN mkdir -p /mnt/sshfs

# Create .ssh directory with correct permissions
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
