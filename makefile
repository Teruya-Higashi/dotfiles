all: permission init link brew

permission:
	chmod +x scripts/*

init:
	scripts/init.sh

link:
	scripts/link.sh

brew:
	scripts/brew.sh
