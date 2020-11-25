#!/usr/bin/env bash

autoflake . -r --remove-all-unused-imports -i
isort . -rc
black .
