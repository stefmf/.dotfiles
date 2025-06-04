.PHONY: lint bootstrap-macos bootstrap-linux dotbot

lint:
	shellcheck $(shell find .bootstrap -type f \( -name '*.sh' -o -name '*.zsh' \)) $(shell find .zsh -type f -name '*.zsh' 2>/dev/null)

bootstrap-macos:
	./.bootstrap/macos/bootstrap_macos.zsh

bootstrap-linux:
	./.bootstrap/linux/bootstrap_linux.sh

dotbot:
	./install -v
