# SSHFS Mount Docker Image

[![Release](https://img.shields.io/github/v/release/techn0phil/sshfs-mount?label=Release&color=%231D9E75)](github.com/techn0phil/sshfs-mount/releases)
[![Trivy](https://img.shields.io/github/actions/workflow/status/techn0phil/sshfs-mount/trivy.yml?logo=github&label=Trivy&labelColor=%23323940)](https://github.com/techn0phil/sshfs-mount/actions/workflows/trivy.yml)
[![Grype](https://img.shields.io/github/actions/workflow/status/techn0phil/sshfs-mount/grype.yml?logo=github&label=Grype&labelColor=%23323940)](https://github.com/techn0phil/sshfs-mount/actions/workflows/grype.yml)

This Docker image provides a container-based SSHFS mount service for mounting remote filesystems over SSH.

## Features

- **Alpine-based**: Lightweight image using Alpine Linux
- **Multi-mount support**: Mount multiple remote filesystems simultaneously
- **Environment-driven configuration**: All settings via environment variables
- **SSH key authentication**: Supports SSH key-based authentication
- **Automatic reconnection**: Built-in reconnect capability for stability
- **Permission handling**: Configurable UID/GID mapping for mounted filesystems

## Environment Variables

Remote filesystems are configured using environment variables with the pattern:

```
SSHFS_REMOTE_<NAME>_<SETTING>
```

For each remote, you need to define:

- `SSHFS_REMOTE_<NAME>_NAME` - Display name for the mount (used for mount point directory)
- `SSHFS_REMOTE_<NAME>_USERNAME` - SSH username
- `SSHFS_REMOTE_<NAME>_HOST` - SSH host
- `SSHFS_REMOTE_<NAME>_PATH` - Remote filesystem path
- `SSHFS_REMOTE_<NAME>_UID` - (Optional) UID for mounted files
- `SSHFS_REMOTE_<NAME>_GID` - (Optional) GID for mounted files

### Example

For a remote named "storage":

```bash
SSHFS_REMOTE_STORAGE_NAME=storage
SSHFS_REMOTE_STORAGE_USERNAME=user
SSHFS_REMOTE_STORAGE_HOST=storage.example.com
SSHFS_REMOTE_STORAGE_PATH=/home/user/data
SSHFS_REMOTE_STORAGE_UID=1000
SSHFS_REMOTE_STORAGE_GID=1000
```

This mounts `user@storage.example.com:/home/user/data` to `/mnt/sshfs/storage`.

## Docker Compose Usage

```yaml
services:
  sshfs-mount:
    image: techn0phil/sshfs-mount:latest
    container_name: sshfs-mount
    restart: unless-stopped
    stop_grace_period: 30s
    privileged: true
    cap_add:
      - SYS_ADMIN
    devices:
      - /dev/fuse
    volumes:
      - ${SSHFS_PRIVATE_KEY_PATH}:/root/.ssh/id_rsa:ro
      - type: bind
        source: ${SSHFS_MOUNT_PATH}
        target: /mnt/sshfs
        bind:
          propagation: rshared
    environment:
      - SSHFS_REMOTE_STORAGE_NAME=storage
      - SSHFS_REMOTE_STORAGE_USERNAME=user
      - SSHFS_REMOTE_STORAGE_HOST=storage.example.com
      - SSHFS_REMOTE_STORAGE_PATH=/home/user/data
      - SSHFS_REMOTE_STORAGE_UID=1000
      - SSHFS_REMOTE_STORAGE_GID=1000
      - SSHFS_REMOTE_BACKUP_NAME=backup
      - SSHFS_REMOTE_BACKUP_USERNAME=backupuser
      - SSHFS_REMOTE_BACKUP_HOST=backup.example.com
      - SSHFS_REMOTE_BACKUP_PATH=/backups
      - SSHFS_REMOTE_BACKUP_UID=1000
      - SSHFS_REMOTE_BACKUP_GID=1000
```

## Building the Image

```bash
docker build -t techn0phil/sshfs-mount:latest .
```

## Security Considerations

- **SSH Keys**: Mount SSH private keys as read-only volumes
- **Host Key Verification**: Disabled by default (`StrictHostKeyChecking=no`). For production, consider using a known_hosts file
- **Permissions**: The image runs as root, which is required for SSHFS mounting

## Mount Points

Mounted filesystems are accessible at:

```
/mnt/sshfs/<NAME>/
```

Where `<NAME>` is the value of `SSHFS_REMOTE_<REMOTE>_NAME`.

## Shutdown Behavior

When the container receives a stop signal, it performs a graceful cleanup:

- Unmounts SSHFS filesystems for all configured remotes
- Unmounts any additional bind/propagated mount layers on each mount point
- Removes mount point directories under `/mnt/sshfs/<NAME>`

This helps avoid stale mounts and busy mount directories after container shutdown.

## Troubleshooting Cleanup

If unmount or cleanup is slow, increase `stop_grace_period` so Docker gives the container enough time to complete unmount operations.

## Logs

Check container logs to verify mounts were successful:

```bash
docker logs <container-name>
```

## Requirements

- Docker with support for FUSE (fusermount)
- Valid SSH private key for authentication
- SSH access to remote hosts
