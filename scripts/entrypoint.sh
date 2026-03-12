#!/bin/bash
set -e

# Ensure correct ownership of the home directory volume.
# On first mount, Docker populates it from the image. On subsequent starts,
# the named volume already has data. Either way, make sure dev owns it.
if [ "$(stat -c '%u' /home/dev 2>/dev/null)" != "501" ]; then
    sudo chown -R dev:dev /home/dev
fi

# Execute the provided command (defaults to zsh)
exec "$@"
