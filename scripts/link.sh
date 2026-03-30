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
mkdir -p ~/.config/git
mkdir -p ~/.config/mise
ln -s $(pwd)/.agents/skills ~/.agents
ln -s $(pwd)/.agents/skills ~/.claude
ln -s $(pwd)/.claude/settings.json ~/.claude/settings.json
ln -s $(pwd)/.claude/statusline.js ~/.claude/statusline.js && chmod +x ~/.claude/statusline.js
ln -s $(pwd)/.takt ~/.takt
ln -s $(pwd)/.config/git/ignore ~/.config/git/ignore
ln -s $(pwd)/.config/mise/config.toml ~/.config/mise/config.toml

GOOGLE_IME_DIR=~/Library/Application\ Support/Google/JapaneseInput
if [ -d "$GOOGLE_IME_DIR" ]; then
    for f in config1.db user_dictionary.db; do
        if [ -e "$GOOGLE_IME_DIR/$f" ] && [ ! -L "$GOOGLE_IME_DIR/$f" ]; then
            mv "$GOOGLE_IME_DIR/$f" "$GOOGLE_IME_DIR/${f}_bk_$(date +"%Y%m%d%I%M%S")"
        fi
        ln -sf $(pwd)/.config/google-japanese-input/$f "$GOOGLE_IME_DIR/$f"
    done
fi
