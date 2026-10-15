#!/bin/zsh

set -eu

project_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
project_name="$(basename -- "$project_dir")"
parent_dir="$(dirname -- "$project_dir")"
archive_path="$parent_dir/${project_name}-$(date +%Y%m%d-%H%M%S).tar.gz"

if [ -e "$archive_path" ]; then
    printf 'An archive with the same name already exists: %s\n' "$archive_path" >&2
    exit 1
fi

tar -czf "$archive_path" -C "$parent_dir" -- "$project_name"

printf 'Finished : %s\n' "$archive_path"
