#!/bin/bash

set -euxo pipefail

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

if [ -e ~/.zshrc ]; then
    mv ~/.zshrc ~/.zshrc_bk_$(date +"%Y%m%d%I%M%S")
fi
ln -s $(pwd)/.zshrc ~/.zshrc

if [ -e ~/.vimrc ]; then
    mv ~/.vimrc ~/.vimrc_bk_$(date +"%Y%m%d%I%M%S")
fi
ln -s $(pwd)/.vimrc ~/.vimrc

mkdir -p ~/.agents
mkdir -p ~/.claude
ln -s $(pwd)/.agents/skills ~/.agents
ln -s $(pwd)/.agents/skills ~/.claude
ln -s $(pwd)/.claude/settings.json ~/.claude/settings.json
ln -s $(pwd)/.claude/statusline.js ~/.claude/statusline.js && chmod +x ~/.claude/statusline.js
