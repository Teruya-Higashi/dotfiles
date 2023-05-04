all: permission init brew link

permission:
	chmod +x scripts/*

init:
	scripts/init.sh

brew:
	scripts/brew.sh

link:
	scripts/link.sh
