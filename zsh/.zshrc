# Enable Powerlevel10k instant prompt. Keep this near the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Oh My Zsh path
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins handled by Oh My Zsh
plugins=(
  git
  fzf-tab
)

# Environment
export MANPAGER="nvim +Man!"
export TERM="xterm-256color"

# Aliases
alias ls='eza -al --icons=auto --color=always --group-directories-first'
alias la='eza -a --icons=auto --color=always --group-directories-first'
alias ll='eza -l --icons=auto --color=always --group-directories-first'
alias lt='eza -aT --icons=auto --color=always --group-directories-first'
alias l.='eza -al --icons=auto --color=always --group-directories-first ../'
alias l..='eza -al --icons=auto --color=always --group-directories-first ../../'
alias l...='eza -al --icons=auto --color=always --group-directories-first ../../../'
alias cls='clear'
alias v='nvim'

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# fzf shell integration
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh

# fzf-tab config
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':fzf-tab:*' switch-group '<' '>'

# Autosuggestions
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Syntax highlighting must be near the end
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Pokemon
pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
