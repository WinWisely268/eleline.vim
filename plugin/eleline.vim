" ============================================================================
" Filename: eleline.vim
" Author: Liu-Cheng Xu
" Fork: winwisely268
" URL: https://github.com/liuchengxu/eleline.vim

" License: MIT License
" =============================================================================
scriptencoding utf-8
if exists('g:loaded_eleline') || v:version < 700
	finish
endif
let g:loaded_eleline = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:font = get(g:, 'eleline_powerline_fonts', get(g:, 'airline_powerline_fonts', 1))
let s:fn_icon = s:font ? get(g:, 'eleline_function_icon', " \uf794 ") : ''
let s:gui = has('gui_running')
let s:is_win = has('win32')
let s:git_branch_cmd = add(s:is_win ? ['cmd', '/c'] : ['bash', '-c'], 'git branch')
let s:git_branch_symbol = s:font ? " \ue0a0 " : ' Git:'
let s:git_branch_star_substituted = s:font ? "  \ue0a0" : '  Git:'
let s:jobs = {}

function! ElelineBufnrWinnr() abort
	let l:bufnr = bufnr('%')
	if !s:gui
		" transform to circled num: nr2char(9311 + l:bufnr)
		let l:bufnr = l:bufnr > 20 ? l:bufnr : nr2char(9311 + l:bufnr).' '
	endif
	return '  '.l:bufnr.' ❖ '.winnr().' '
endfunction

function! ElelineTotalBuf() abort
	return '[TOT:'.len(filter(range(1, bufnr('$')), 'buflisted(v:val)')).']'
endfunction

function! ElelinePaste() abort
	return &paste ? 'PASTE ' : ''
endfunction

function! ElelineFsize(f) abort
	let l:size = getfsize(expand(a:f))
	if l:size == 0 || l:size == -1 || l:size == -2
		return ''
	endif
	if l:size < 1024
		let size = l:size.' bytes'
	elseif l:size < 1024*1024
		let size = printf('%.1f', l:size/1024.0).'k'
	elseif l:size < 1024*1024*1024
		let size = printf('%.1f', l:size/1024.0/1024.0) . 'm'
	else
		let size = printf('%.1f', l:size/1024.0/1024.0/1024.0) . 'g'
	endif
	return '  '.size.' '
endfunction

function! ElelineCurFname() abort
	return &filetype ==# 'startify' ? '' : '  '.expand('%:p:t').' '
endfunction

function! ElelineError() abort
	if exists('g:loaded_ale')
		let s:ale_counts = ale#statusline#Count(bufnr(''))
		return s:ale_counts[0] == 0 ? '' : '•'.s:ale_counts[0].' '
	endif
	return ''
endfunction

function! ElelineWarning() abort
	if exists('g:loaded_ale')
		" Ensure ElelineWarning() is called after ElelineError() so that s:ale_counts can be reused.
		return s:ale_counts[1] == 0 ? '' : '•'.s:ale_counts[1].' '
	endif
	return ''
endfunction

function! s:is_tmp_file() abort
	if !empty(&buftype)
				\ || index(['startify', 'gitcommit'], &filetype) > -1
				\ || expand('%:p') =~# '^/tmp'
		return 1
	else
		return 0
	endif
endfunction

" Reference: https://github.com/chemzqm/vimrc/blob/master/statusline.vim
function! ElelineGitBranch(...) abort
	if s:is_tmp_file() | return '' | endif
	let reload = get(a:, 1, 0) == 1
	if exists('b:eleline_branch') && !reload | return b:eleline_branch | endif
	if !exists('*FugitiveExtractGitDir') | return '' | endif
	let dir = exists('b:git_dir') ? b:git_dir : FugitiveExtractGitDir(resolve(expand('%:p')))
	if empty(dir) | return '' | endif
	let b:git_dir = dir
	let roots = values(s:jobs)
	let root = fnamemodify(dir, ':h')
	if index(roots, root) >= 0 | return '' | endif

	let argv = add(has('win32') ? ['cmd', '/c']: ['bash', '-c'], 'git branch')
	if exists('*job_start')
		let job = job_start(s:git_branch_cmd, {'out_io': 'pipe', 'err_io':'null', 'out_cb': function('s:out_cb')})
		if job_status(job) ==# 'fail' | return '' | endif
		let s:cwd = root
		let job_id = matchstr(job, '\d\+')
		let s:jobs[job_id] = root
	elseif exists('*jobstart')
		let job_id = jobstart(s:git_branch_cmd, {
					\ 'cwd': root,
					\ 'stdout_buffered': v:true,
					\ 'stderr_buffered': v:true,
					\ 'on_exit': function('s:on_exit')
					\})
		if job_id == 0 || job_id == -1 | return '' | endif
		let s:jobs[job_id] = root
	elseif exists('g:loaded_fugitive')
		let l:head = fugitive#head()
		return empty(l:head) ? '' : s:git_branch_symbol.l:head . ' '
	endif

	return ''
endfunction

function! s:out_cb(channel, message) abort
	if a:message =~# '^* '
		let l:job_id = ch_info(a:channel)['id']
		if !has_key(s:jobs, l:job_id) | return | endif
		let l:branch = substitute(a:message, '*', s:git_branch_star_substituted, '')
		call s:SetGitBranch(s:cwd, l:branch.' ')
		call remove(s:jobs, l:job_id)
	endif
endfunction

function! s:on_exit(job_id, data, _event) dict abort
	if !has_key(s:jobs, a:job_id) | return | endif
	if v:dying | return | endif
	let l:cur_branch = join(filter(self.stdout, 'v:val =~# "*"'))
	if !empty(l:cur_branch)
		let l:branch = substitute(l:cur_branch, '*', s:git_branch_star_substituted, '')
		call s:SetGitBranch(self.cwd, l:branch.' ')
	else
		let err = join(self.stderr)
		if !empty(err) | echoerr err | endif
	endif
	call remove(s:jobs, a:job_id)
endfunction

function! s:SetGitBranch(root, str) abort
	let buf_list = filter(range(1, bufnr('$')), 'bufexists(v:val)')
	let root = a:root
	for nr in buf_list
		let path = fnamemodify(bufname(nr), ':p')
		if match(path, root) >= 0
			call setbufvar(nr, 'eleline_branch', a:str)
		endif
	endfor
	redraws!
endfunction

function! ElelineGitStatus() abort
	let l:summary = [0, 0, 0]
	if exists('b:sy')
		let l:summary = b:sy.stats
	elseif exists('b:gitgutter.summary')
		let l:summary = b:gitgutter.summary
	endif
	if max(l:summary) > 0
		return ' +'.l:summary[0].' ~'.l:summary[1].' -'.l:summary[2].' '
	endif
	return ''
endfunction

function! ElelineLCN() abort
	if !exists('g:LanguageClient_loaded') | return '' | endif
	return eleline#LanguageClientNeovim()
endfunction

function! ElelineVista() abort
	return !empty(get(b:, 'vista_nearest_method_or_function', '')) ? s:fn_icon.b:vista_nearest_method_or_function : ''
endfunction

function! ElelineCoc() abort
	if s:is_tmp_file() | return '' | endif
	if get(g:, 'coc_enabled', 0) | return coc#status().' ' | endif
	return ''
endfunction

" https://github.com/liuchengxu/eleline.vim/wiki
function! s:StatusLine() abort
	function! s:def(fn) abort
		return printf('%%#%s#%%{%s()}%%*', a:fn, a:fn)
	endfunction
	let l:bufnr_winnr = s:def('ElelineBufnrWinnr')
	let l:paste = s:def('ElelinePaste')
	let l:curfname = s:def('ElelineCurFname').'%m%r'
	let l:branch = s:def('ElelineGitBranch')
	let l:status = s:def('ElelineGitStatus')
	let l:error = s:def('ElelineError')
	let l:warning = s:def('ElelineWarning')
	let l:tags = '%{exists("b:gutentags_files") ? gutentags#statusline() : ""} '
	let l:lcn = '%{ElelineLCN()}'
	let l:coc = '%{ElelineCoc()}'
	let l:vista = '%#ElelineVista#%{ElelineVista()}%*'
	let l:prefix = l:bufnr_winnr.l:paste
	if get(g:, 'eleline_slim', 0)
		return l:prefix.'%<'.l:common
	endif
	let l:tot = s:def('ElelineTotalBuf')
	let l:fsize = '%#ElelineFsize#%{ElelineFsize(@%)}'
	let l:m_r_f = '%#Eleline7# %y %*'
	let l:pos = '%#Eleline8# '.(s:font?"\ue0a1":'').'%l/%L:%c%V '
	let l:enc = ' %{&fenc != "" ? &fenc : &enc} | %{&bomb ? ",BOM " : ""}'
	let l:ff = '%{&ff} %*'
	let l:pct = '%#Eleline9# %P %*'
	let l:common = l:paste.l:curfname.l:branch.' '.l:status.l:error.l:warning.l:tags.l:lcn.l:coc.l:vista
	return l:common
				\ .'%='.l:m_r_f.l:pct.l:pos.l:fsize " .l:enc.l:ff.l:pct
endfunction

let s:colors = {
			\   140 : '#81A2BE',
			\		149 : '#81A2BE',
			\		160 : '#81A2BE',
			\   171 : '#B5BD68',
			\   178 : '#B294BB',
			\   184 : '#B294BB',
			\   208 : '#CC6666',
			\   232 : '#CC6666', 197 : '#CC6666',
			\   214 : '#F0C674', 124 : '#F0C674', 172 : '#F0C674',
			\   32  : '#DE935F', 89  : '#DE935F',
			\
			\   235 : '#1d1f21', 236 : '#282a2e', 237 : '#373b41',
			\   238 : '#3F4142', 239 : '#484a4D', 240 : '#55585E',
			\   241 : '#6D7179', 242 : '#666666', 243 : '#767676',
			\   244 : '#808080', 245 : '#8a8a8a', 246 : '#969896',
			\   247 : '#9e9e9e', 248 : '#a8a8a8', 249 : '#d8dee9',
			\   250 : '#e5e9f0', 251 : '#eceff4', 252 : '#d0d0d0',
			\   253 : '#dadada', 254 : '#e4e4e4', 255 : '#eeeeee',
			\ }

function! s:extract(group, what, ...) abort
	if a:0 == 1
		return synIDattr(synIDtrans(hlID(a:group)), a:what, a:1)
	else
		return synIDattr(synIDtrans(hlID(a:group)), a:what)
	endif
endfunction

if !exists('g:eleline_background')
	let s:normal_bg = s:extract('Normal', 'bg', 'cterm')
	if s:normal_bg >= 233 && s:normal_bg <= 243
		let s:bg = s:normal_bg
	else
		let s:bg = 235
	endif
else
	let s:bg = g:eleline_background
endif

" Don't change in gui mode
if has('termguicolors') && &termguicolors
	let s:bg = 235
endif

function! s:hi(group, dark, light, ...) abort
	let [fg, bg] = &bg ==# 'dark' ? a:dark : a:light

	if empty(bg) && &bg ==# 'light'
		let reverse = s:extract('StatusLine', 'reverse')
		let ctermbg = s:extract('StatusLine', reverse ? 'fg' : 'bg', 'cterm')
		let guibg = s:extract('StatusLine', reverse ? 'fg': 'bg' , 'gui')
	else
		let ctermbg = bg
		let guibg = s:colors[bg]
	endif
	execute printf('hi %s ctermfg=%d guifg=%s ctermbg=%d guibg=%s',
				\ a:group, fg, s:colors[fg], ctermbg, guibg)
	if a:0 == 1
		execute printf('hi %s cterm=%s gui=%s', a:group, a:1, a:1)
	endif
endfunction

function! s:hi_statusline() abort
	call s:hi('ElelineBufnrWinnr' , [232 , 178]	, [89 , '']  )
	call s:hi('ElelineTotalBuf'   , [178 , s:bg+6] , [240 , ''] )
	call s:hi('ElelinePaste'		,		[232 , 178]	, [232 , 178]	, 'bold')
	call s:hi('ElelineFsize'		,		[250 , s:bg+4] , [235 , ''] )
	call s:hi('ElelineCurFname'   , [236 , 140] , [171 , '']	 , 'bold' )
	call s:hi('ElelineGitBranch'  , [171 , s:bg+2] , [89  , '']	 , 'bold' )
	call s:hi('ElelineGitStatus'  , [89, s:bg+2] , [89  , ''])
	call s:hi('ElelineError'		,		[197 , s:bg+2] , [197 , ''])
	call s:hi('ElelineWarning'	,		[214 , s:bg+2] , [214 , ''])
	call s:hi('ElelineVista'		,		[149 , s:bg+2] , [149 , ''])

	if &bg ==# 'dark'
		call s:hi('StatusLine' , [140 , s:bg+1], [140, ''] , 'none')
	endif

	call s:hi('Eleline7'		, [249 , s:bg+6], [237, ''] )
	call s:hi('Eleline8'		, [250 , s:bg+3], [238, ''] )
	call s:hi('Eleline9'		, [251 , 89], [239, ''] )
endfunction

function! s:InsertStatuslineColor(mode) abort
	if a:mode ==# 'i'
		call s:hi('ElelineCurFname' , [235, 171] , [251, 171])
	elseif a:mode ==# 'r'
		call s:hi('ElelineCurFname' , [232, 160], [232, 160])
	else
		call s:hi('ElelineCurFname' , [232, 178], [89, ''])
	endif
endfunction

" Note that the "%!" expression is evaluated in the context of the
" current window and buffer, while %{} items are evaluated in the
" context of the window that the statusline belongs to.
function! s:SetStatusLine(...) abort
	call ElelineGitBranch(1)
	let &l:statusline = s:StatusLine()
	" User-defined highlightings shoule be put after colorscheme command.
	call s:hi_statusline()
endfunction

if exists('*timer_start')
	call timer_start(100, function('s:SetStatusLine'))
else
	call s:SetStatusLine()
endif

augroup eleline
	autocmd!
	autocmd User GitGutter,Startified,LanguageClientStarted call s:SetStatusLine()
	" Change colors for insert mode
	autocmd InsertLeave * call s:hi('ElelineCurFname', [236, 140], [89, ''])
	autocmd InsertEnter,InsertChange * call s:InsertStatuslineColor(v:insertmode)
	autocmd BufWinEnter,ShellCmdPost,BufWritePost * call s:SetStatusLine()
	autocmd FileChangedShellPost,ColorScheme * call s:SetStatusLine()
	autocmd FileReadPre,ShellCmdPost,FileWritePost * call s:SetStatusLine()
augroup END

let &cpoptions = s:save_cpo
unlet s:save_cpo
