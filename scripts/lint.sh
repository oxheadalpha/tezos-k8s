#!/usr/bin/env bash
set -x

autoflake . -r --remove-all-unused-imports -i
isort . -rc --skip-glob *.venv*
black .
