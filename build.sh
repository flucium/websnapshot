#!/bin/zsh

set -eu

if (( $# > 1 )); then
    print -u2 "Usage: zsh ${0:t} [debug|release|clean]"
    exit 1
fi

action=build

case "${1:-debug}" in
    debug)
        configuration=Debug
        ;;
    release)
        configuration=Release
        ;;
    clean)
        configuration=Debug
        action=clean
        ;;
    *)
        print -u2 "Usage: zsh ${0:t} [debug|release|clean]"
        exit 1
        ;;
esac

exec xcodebuild \
    -project "${0:A:h}/WebSnapshot.xcodeproj" \
    -scheme WebSnapshot \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    "$action"
