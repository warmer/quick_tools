" display line numbers in buffers
set number

" use all mouse modes (normal, visual, insert, command-line)
set mouse=a

" set the placeholder '>-' for tabs
" show '~' for trailing spaced
" show '>' in the last column when 'wrap' is off and line wraps
" show '<' in the first column when 'wrap' is off and previous line wrapped
set listchars=tab:>-,trail:~,extends:>,precedes:<
" display unprintable characters (spaces, tabs)
set list

" enable filetype detection
filetype on
" override filetype detection to ensure .h.erb files are interpreted as C
au BufNewFile,BufRead *.h.erb set filetype=c
" end lines with <NL>
set ff=unix

" tabs represent two spaced by default
set tabstop=2
" set auto-indentation click point from the beginning of the line
set shiftwidth=2
" typically set to tabstop value
set softtabstop=2
" replace tabs with spaces always
set expandtab
" copy indentation from the previous line
set autoindent

" enable enhanced autocompletion (show options above the command)
set wildmenu
" briefly show the matching bracket, when inserted and already on-screen
set showmatch
" when typing a search command, jump to first pattern, if match found
set incsearch
" highlight all matches of a search pattern
set hlsearch

" enable syntax highlighting
syntax on
