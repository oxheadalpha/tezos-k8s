#!/bin/sh

if [ "$(DRY_RUN)" == "false" ];
then
  extra_args="--confirm"
else
  extra_args="--dry-run"
fi

npm run pay -- ${extra_args} --work-dir /breadcrumbs
