#!/bin/bash
if [[ "$SSH_ORIGINAL_COMMAND" == "rsync --server "*" /var/www/html/" ]]; then
    exec $SSH_ORIGINAL_COMMAND
else
    echo "Rejected command: $SSH_ORIGINAL_COMMAND" >&2
    exit 1
fi
