SHELL := /usr/bin/env bash

.PHONY: latest stable all-linux all-windows deb clean

latest:
	./scripts/download-latest.sh --channel latest --platform auto

stable:
	./scripts/download-latest.sh --channel stable --platform auto

all-linux:
	./scripts/download-latest.sh --channel latest --platform all

all-windows:
	./scripts/download-latest.sh --channel latest --platform all-windows

deb:
	./scripts/download-deb-latest.sh --channel latest

clean:
	rm -rf dist
