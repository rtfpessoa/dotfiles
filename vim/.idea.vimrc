"" Source your .vimrc
"source ~/.vimrc

set relativenumber
set number

set clipboard=unnamed

" Find more examples here: https://jb.gg/share-ideavimrc
"" -- Suggested options --
" Show a few lines of context around the cursor. Note that this makes the
" text scroll if you mouse-click near the start or end of the window.
set scrolloff=5

" Do incremental searching.
set incsearch

" Don't use Ex mode, use Q for formatting.
map Q gq

" Remap commands to yanking on most commands
vnoremap p "_dP
nnoremap d "_d
nnoremap c "_c
vnoremap c "_c

"" -- Map IDE actions to IdeaVim -- https://jb.gg/abva4t
"" Map \r to the Reformat Code action
"map \r <Action>(ReformatCode)

"" Map <leader>d to start debug
"map <leader>d <Action>(Debug)

"" Map \b to toggle the breakpoint on the current line
"map \b <Action>(ToggleLineBreakpoint)


" Find more examples here: https://jb.gg/share-ideavimrc

let mapleader = " "
map <leader>b <Action>(ToggleLineBreakpoint)
map <leader>r <Action>(RenameElement)
map <leader>ff <Action>(GotoFile)
map <leader>fc <Action>(GotoClass)
nmap [[ <Action>(MethodUp)
nmap ]] <Action>(MethodDown)
map gh <Action>(ShowErrorDescription)

nnoremap gi :action GotoImplementation<CR>
nnoremap gd :action GotoDeclaration<CR>
nnoremap gp :action GotoSuperMethod<CR>
nnoremap gr :action FindUsages<CR>
