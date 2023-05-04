#!/bin/bash

set -euo pipefail

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

brew bundle

# if [ ! -e $(pwd)/zsh-completions-chmod-done.tmp ]; then
# 	chmod -R go-w '/opt/homebrew/share'
# 	touch $(pwd)/zsh-completions-chmod-done.tmp
# fi
