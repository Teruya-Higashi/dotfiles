typeset -U path PATH
path=(
  $HOME/.local/share/mise/shims(N-/)
  /opt/homebrew/bin(N-/)
  /opt/homebrew/sbin(N-/)
  /usr/bin
  /usr/sbin
  /bin
  /sbin
  /usr/local/bin(N-/)
  /usr/local/sbin(N-/)
  /Library/Apple/usr/bin
)

# envs
export HISTSIZE=20000

# colors
export LSCOLORS=gxfxcxdxcxegedabagacad
alias ls="ls -GF"
autoload -Uz colors && colors

# activate zsh-completions and zsh-autosuggestions
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  autoload -Uz compinit && compinit
  zstyle ':completion:*:default' menu select=1
fi

# activate gitprompt
source "$(echo $HOME)/.zsh/git-prompt.zsh"

# set gitprompt
# ref. https://github.com/woefe/git-prompt.zsh#appearance
ZSH_THEME_GIT_PROMPT_PREFIX="[ "
ZSH_THEME_GIT_PROMPT_SUFFIX=" ]"
ZSH_THEME_GIT_PROMPT_SEPARATOR=" | "
ZSH_THEME_GIT_PROMPT_DETACHED="%{$fg[cyan]%}:"
ZSH_THEME_GIT_PROMPT_BRANCH="%{$fg[magenta]%}"
ZSH_THEME_GIT_PROMPT_UPSTREAM_SYMBOL="%{$fg_bold[yellow]%} ⟳ "
ZSH_THEME_GIT_PROMPT_UPSTREAM_NO_TRACKING="%{$fg_bold[red]%} !"
ZSH_THEME_GIT_PROMPT_UPSTREAM_PREFIX="%{$fg[red]%}(%{$fg[yellow]%}"
ZSH_THEME_GIT_PROMPT_UPSTREAM_SUFFIX="%{$fg[red]%})"
ZSH_THEME_GIT_PROMPT_BEHIND="%{$fg[red]%} ↓"
ZSH_THEME_GIT_PROMPT_AHEAD="%{$fg[blue]%} ↑"
ZSH_THEME_GIT_PROMPT_UNMERGED="%{$fg[red]%}x"
ZSH_THEME_GIT_PROMPT_STAGED="%{$fg[blue]%}#"
ZSH_THEME_GIT_PROMPT_UNSTAGED="%{$fg[red]%}+"
ZSH_THEME_GIT_PROMPT_UNTRACKED=".."
ZSH_THEME_GIT_PROMPT_STASHED="%{$fg[blue]%}$"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[green]%}--"

# for prompt variables
local user="%{$fg[yellow]%}%n%{$reset_color%}"
local host="%{$fg[cyan]%}@%m%{$reset_color%}"
local pwd="%{$fg[cyan]%}%~%{$reset_color%}"
local head="%{$fg[white]%}%(!.#.$)%"

prompt_with_git_status() {
  if [ "$(git rev-parse --is-inside-work-tree 2> /dev/null)" = true ]; then
    PROMPT="${user} : ${pwd} $(gitprompt)"$'\n'"${head}  "
  else
    PROMPT="${user} : ${pwd}"$'\n'"${head}  "
  fi
}

add_newline() {
  if [[ -z $PS1_NEWLINE_LOGIN ]]; then
    PS1_NEWLINE_LOGIN=true
  else
    printf '\n'
  fi
}

precmd() {
  prompt_with_git_status
  add_newline
}

# set mise
eval "$(mise activate zsh)"
