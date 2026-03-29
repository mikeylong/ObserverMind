SHELL := /bin/zsh

INSTALL_DIR ?= $(HOME)/.local/bin

.PHONY: build release test install uninstall

build:
	swift build

release:
	swift build -c release --product observer

test:
	swift test

install:
	INSTALL_DIR="$(INSTALL_DIR)" ./scripts/install.sh

uninstall:
	INSTALL_DIR="$(INSTALL_DIR)" ./scripts/uninstall.sh
