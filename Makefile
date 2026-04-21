.PHONY: install install-dry install-force deps recon recon-unlocked badges bindings wire uninstall help

SHELL := /usr/bin/env bash
ROOT := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

help:
	@echo "tmux-attic make targets:"
	@echo "  install          Full wiring + deps (tmux.conf, recon, badges, ignore keys)"
	@echo "  install-dry      Preview everything — no files touched"
	@echo "  install-force    Full install; append even if stray attic lines found outside sentinels"
	@echo "  wire             Only wire session_manager.tmux into tmux.conf"
	@echo "  deps             Only install deps (recon, badges, ignore bindings)"
	@echo "  recon            Install recon only (cargo install --locked)"
	@echo "  recon-unlocked   Install recon without --locked (for lockfile-v4 vs old cargo)"
	@echo "  badges           Only run install_badges.sh --yes"
	@echo "  bindings         Only add @recon-ignore toggle keys to tmux.conf"
	@echo "  uninstall        Strip tmux.conf managed blocks (badges hooks untouched)"

install:
	@$(ROOT)install.sh

install-dry:
	@$(ROOT)install.sh --dry-run

install-force:
	@$(ROOT)install.sh --force

recon:
	@$(ROOT)install_claude_deps.sh --skip-badges --skip-bindings

recon-unlocked:
	@$(ROOT)install_claude_deps.sh --skip-badges --skip-bindings --no-locked

wire:
	@$(ROOT)install.sh --skip-deps

deps:
	@$(ROOT)install.sh --skip-tmux-wire

badges:
	@$(ROOT)install_badges.sh --yes

bindings:
	@$(ROOT)install_claude_deps.sh --skip-recon --skip-badges

uninstall:
	@$(ROOT)install.sh --uninstall
