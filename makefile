all: permission init install link

permission:
	chmod +x scripts/*

init:
	scripts/init.sh

install:
	scripts/install.sh

link:
	scripts/link.sh
