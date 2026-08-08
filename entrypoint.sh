#!/bin/bash
set -e

MOUNTED_POINTS=()
CLEANED_UP=0

unmount_mountpoint_layers() {
    TARGET_MOUNT="$1"
    ATTEMPTS=0

    while [ "$ATTEMPTS" -lt 20 ]; do
        # Collect all mount targets at/under the mount point, deepest first.
        MAP=$(awk -v mp="$TARGET_MOUNT" '$5 == mp || index($5, mp "/") == 1 { print $5 }' /proc/self/mountinfo | sort -r -u)

        if [ -z "$MAP" ]; then
            break
        fi

        # First pass: try a recursive lazy unmount from the root mount point.
        umount -R -l "$TARGET_MOUNT" 2>/dev/null || true

        # Second pass: unmount each discovered layer explicitly.
        while read -r LAYER; do
            [ -n "$LAYER" ] || continue
            fusermount -uz "$LAYER" 2>/dev/null || umount -l "$LAYER" 2>/dev/null || true
        done << EOF
$MAP
EOF

        ATTEMPTS=$((ATTEMPTS + 1))
    done
}

cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return
    fi
    CLEANED_UP=1

    echo "Stopping container, unmounting SSHFS remotes..."

    # Unmount in reverse order to avoid mount dependency issues.
    for (( i=${#MOUNTED_POINTS[@]}-1; i>=0; i-- )); do
        MOUNT_POINT="${MOUNTED_POINTS[$i]}"

        # A mount point can have multiple layers (sshfs + bind mount + propagated layers).
        unmount_mountpoint_layers "$MOUNT_POINT"

        if [ -d "$MOUNT_POINT" ]; then
            if ! rmdir "$MOUNT_POINT" 2>/dev/null; then
                if [[ "$MOUNT_POINT" == /mnt/sshfs/* ]]; then
                    rm -rf -- "$MOUNT_POINT" 2>/dev/null || echo "Warning: Could not remove mount directory $MOUNT_POINT"
                else
                    echo "Warning: Refusing force delete outside /mnt/sshfs: $MOUNT_POINT"
                fi
            fi
        fi

        echo "Unmounted $MOUNT_POINT"
    done

    echo "Unmount cleanup completed"
}

on_term() {
    cleanup
    exit 0
}

trap on_term TERM INT
trap cleanup EXIT

# Configure FUSE to allow other users to access mounts
cat > /etc/fuse.conf << EOF
user_allow_other
EOF

# Configure SSH to avoid host key verification issues
mkdir -p /root/.ssh
cat > /root/.ssh/config << EOF
Host *
    StrictHostKeyChecking=no
    UserKnownHostsFile=/dev/null
    LogLevel=ERROR
EOF
chmod 600 /root/.ssh/config

# Find all SSHFS_REMOTE_* environment variables and extract unique remote names
# Pattern: SSHFS_REMOTE_<NAME>_<SETTING>
REMOTES=$(env | awk -F= '/^SSHFS_REMOTE_[A-Z0-9_]+_[A-Z0-9_]+=/ { key=$1; sub(/^SSHFS_REMOTE_/, "", key); sub(/_[^_]+$/, "", key); print key }' | sort -u)

if [ -z "$REMOTES" ]; then
    echo "No SSHFS_REMOTE_* environment variables found"
    # Keep container running until stopped.
    tail -f /dev/null &
    wait $!
    exit 0
fi

# Mount each remote filesystem
for REMOTE in $REMOTES; do
    PREFIX="SSHFS_REMOTE_${REMOTE}"
    
    # Get remote configuration
    NAME="${PREFIX}_NAME"
    USERNAME="${PREFIX}_USERNAME"
    HOST="${PREFIX}_HOST"
    PATH_VAR="${PREFIX}_PATH"
    UID_VAR="${PREFIX}_UID"
    GID_VAR="${PREFIX}_GID"
    
    NAME_VALUE="${!NAME}"
    USERNAME_VALUE="${!USERNAME}"
    HOST_VALUE="${!HOST}"
    PATH_VALUE="${!PATH_VAR}"
    UID_VALUE="${!UID_VAR}"
    GID_VALUE="${!GID_VAR}"
    
    # Validate required fields
    if [ -z "$NAME_VALUE" ] || [ -z "$USERNAME_VALUE" ] || [ -z "$HOST_VALUE" ] || [ -z "$PATH_VALUE" ]; then
        echo "Warning: Incomplete configuration for $REMOTE (skipping)"
        continue
    fi
    
    # Create mount point
    MOUNT_POINT="/mnt/sshfs/${NAME_VALUE}"
    mkdir -p "$MOUNT_POINT"
    mount --bind "$MOUNT_POINT" "$MOUNT_POINT"
    mount --make-rshared "$MOUNT_POINT"
    
    # Build SSHFS options with SSH flags for better connection stability
    SSHFS_OPTS="-o allow_other,max_conns=4,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,compression=no,cache=yes,kernel_cache,auto_cache"
    
    # Add UID and GID if specified
    if [ -n "$UID_VALUE" ] && [ -n "$GID_VALUE" ]; then
        SSHFS_OPTS="${SSHFS_OPTS},uid=${UID_VALUE},gid=${GID_VALUE}"
    fi
    
    # Mount the remote filesystem
    echo "Mounting ${USERNAME_VALUE}@${HOST_VALUE}:${PATH_VALUE} to ${MOUNT_POINT}"
    if ! sshfs "${USERNAME_VALUE}@${HOST_VALUE}:${PATH_VALUE}" "$MOUNT_POINT" $SSHFS_OPTS 2>&1; then
        echo "Error: Failed to mount $REMOTE"
        continue
    fi
    MOUNTED_POINTS+=("$MOUNT_POINT")
    
    echo "Successfully mounted $REMOTE"
done

echo "All SSHFS mounts completed"

# Keep container running until stopped.
tail -f /dev/null &
wait $!
