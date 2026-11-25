#!/bin/zsh

# e.g. zsh ./copyright.sh ./WebSnapshot/WebSnapshotApp.swift

set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <file>" >&2
    exit 1
fi

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

LICENSE_FILE="$ROOT_DIR/LICENSE"

case "$1" in
    /*) TARGET_FILE="$1" ;;
    *)  TARGET_FILE="$ROOT_DIR/$1" ;;
esac

if [ ! -f "$LICENSE_FILE" ]; then
    echo "Error: LICENSE not found." >&2
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "Error: Target file not found." >&2
    exit 1
fi

TEMP_FILE=$(mktemp "${TARGET_FILE}.tmp.XXXXXX")

trap 'rm -f "$TEMP_FILE"' 0

cp -p "$TARGET_FILE" "$TEMP_FILE"

{
    
    awk '{ print "// " $0 }' "$LICENSE_FILE"

    
    printf '\n\n\n'

   
    cat "$TARGET_FILE"

} > "$TEMP_FILE"

mv -f "$TEMP_FILE" "$TARGET_FILE"

trap - 0

echo "Copyright header added: $TARGET_FILE"

