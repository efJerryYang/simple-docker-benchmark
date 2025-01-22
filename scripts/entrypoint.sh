#!/bin/bash

/benchmark/benchmark.sh

if [ "$KEEP_RUNNING" = "true" ]; then
    echo "Keeping container running..."
    tail -f /dev/null
fi

