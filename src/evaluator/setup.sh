#!/usr/bin/env bash

# Compare versions according to opam's version comparison
compareVersions() {
    if [ "$1" = "$2" ]; then printf eq; return 0; fi
    greater="$( ( printf "%s\n" "$1"; printf "%s\n" "$2" ) | sort -V | head -n1)"
    if [ "$greater" = "$1" ]; then printf gt
    elif [ "$greater" = "$2" ]; then printf lt
    else return 1
    fi
}

# Execute, skipping empty arguments
_() {
    args=()
    for arg in "$@"; do
        if [ -n "$arg" ]; then
            args+=("$arg")
        fi
    done
    "${args[@]}"
}