#!/bin/bash

# Check which variant we should download
if [ "`uname`" = "Darwin" ]; then
  VARIANT=osx
else
  VARIANT=linux
fi
echo "$VARIANT"
echo "$LOCKIT_GITHUB_TOKEN"
