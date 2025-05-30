.PHONY: lint bootstrap-macos bootstrap-linux dotbot

lint:
	shellcheck .bootstrap/**/*.sh

bootstrap-macos:
	./.bootstrap/macos/bootstrap_macos.zsh

bootstrap-linux:
	./.bootstrap/linux/bootstrap_linux.sh

dotbot:
	./install -v
