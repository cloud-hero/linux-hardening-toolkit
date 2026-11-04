#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export LIMA_HOME="$PWD/.lab/lima"
exec "$PWD/.lab/tools/bin/limactl" "$@"
