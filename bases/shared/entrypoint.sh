#!/bin/bash
set -x
set +e

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPTS_DIRECTORY="$HOME/entrypoint"

mkdir --parents "$SCRIPTS_DIRECTORY"
tar --directory="$SCRIPTS_DIRECTORY" --extract --file="$DIRECTORY_PATH/entrypoint.tar.gz" --gzip

/bin/bash "$SCRIPTS_DIRECTORY/main.sh"
