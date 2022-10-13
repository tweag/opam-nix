#!/bin/sh

set -eu

"$1" | grep -q "Hello, world"
