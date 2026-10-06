#!/bin/zsh
# Double-click in Finder to build and publish the saved project to Cloudflare.
cd -- "${0:A:h}" || exit 1
/usr/bin/python3 UpdateService/publish_update.py "$@"
publish_result=$?
if [[ -t 0 ]]; then
  printf '\nPress Return to close this window.'
  read -r
fi
exit "$publish_result"
