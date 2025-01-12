# Simulate posix export
# Does not work with command capture `$(...)` since that is not valid fish
function export --description 'Set env variable. Alias for `set -gx` for bash compatibility.'
    if not set -q argv[1]
        set -x
        return 0
    end
    for arg in $argv
        set -l v (string split -m 1 "=" -- $arg)
        switch (count $v)
            case 1
                set -gx $v $$v
            case 2
                if contains -- $v[1] PATH
                    echo "Use 'add_path' instead"
                    return 1
                else if contains -- $v[1] CDPATH MANPATH
                    set -l colonized_path (string replace -- "$$v[1]" (string join ":" -- $$v[1]) $v[2])
                    set -gx $v[1] (string split ":" -- $colonized_path)
                else
                    # status is 1 from the contains check, and `set` does not change the status on success: reset it.
                    true
                    set -gx $v[1] $v[2]
                end
        end
    end
end

function add_path -d "Add directory to PATH" -a path
    fish_add_path --global --path --move --prepend "$path"
end

function md -d "Create a new directory and enter it" -a name
    mkdir -p "$name"; and cd "$name"
end

function f -d "find shorthand" -a iname type
    set -l typeArgs ""
    if [ -n "$type" ]
        set -l typeArgs "-type $type"
    end
    find . $typeArgs -iname "$iname" 2>/dev/null
end

function server -d "Start an HTTP server from a directory, optionally specifying the port" -a port
    set -q port[1]
    or set port 8000
    open "http://localhost:$port/"
    # Set the default Content-Type to `text/plain` instead of `application/octet-stream`
    # And serve everything as UTF-8 (although not technically correct, this doesn’t break anything for binary files)
    python -c \$'import SimpleHTTPServer;\nmap = SimpleHTTPServer.SimpleHTTPRequestHandler.extensions_map;\nmap[""] = "text/plain";\nfor key, value in map.items():\n\tmap[key] = value + ";charset=UTF-8";\nSimpleHTTPServer.test();' "$port"
end

function cp_p -d "Copy w/ progress" -a source destination
    rsync -WavP --human-readable --progress $source $destination
end

function gz -d "Get gzipped size" -a target
    echo "orig size    (bytes): "
    cat "$target" | wc -c
    echo "gzipped size (bytes): "
    gzip -c "$target" | wc -c
end

function whois -d "Whois a domain or a URL" -a url
    set -l domain (echo "$url" | awk -F/ '{print $3}') # get domain from URL
    if test -z $domain
        set -l domain $url
    end
    echo "Getting whois record for: $domain ..."

    # avoid recursion
    # this is the best whois server
    # strip extra fluff
    /usr/bin/whois -h whois.internic.net $domain | sed '/NOTICE:/q'
end

function strip_diff_leading_symbols
    set -l color_code_regex "(\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K])"
    set -l reset_color "\x1B\[m"
    set -l dim_magenta "\x1B\[38;05;146m"

    # simplify the unified patch diff header
    sed -r "s/^($color_code_regex)diff --git .*\$//g" | sed -r "s/^($color_code_regex)index .*\$/\n\1\$(rule)/g" | sed -r "s/^($color_code_regex)\+\+\+(.*)\$/\1+++\5\n\1\$(rule)\x1B\[m/g" | \
        # extra color for @@ context line
        sed -r "s/@@$reset_color $reset_color(.*\$)/@@ $dim_magenta\1/g" | \
        # actually strips the leading symbols
        sed -r "s/^($color_code_regex)[\+\-]/\1 /g"
end

function camerausedby -d "Who is using the laptop's iSight camera?"
    echo "Checking to see who is using the iSight camera… 📷"
    set usedby (lsof | grep -w "AppleCamera\|USBVDC\|iSight" | awk '{printf $2"\n"}' | xargs ps)
    echo -e "Recent camera uses:\n$usedby"
end

# From alex sexton gist.github.com/SlexAxton/4989674
function gifify -d "Generate animated gifs from any video" -a video quality
    if test -n "$video"
        if $quality -eq --good
            ffmpeg -i $video -r 10 -vcodec png out-static-%05d.png
            time convert -verbose +dither -layers Optimize -resize 900x900\> out-static*.png GIF:- | gifsicle --colors 128 --delay=5 --loop --optimize=3 --multifile - >$video.gif
            rm out-static*.png
        else
            ffmpeg -i $video -s 600x400 -pix_fmt rgb24 -r 10 -f gif - | gifsicle --optimize=3 --delay=3 >$video.gif
        end
    else
        echo "proper usage: gifify <input_movie.mov>. You DO need to include extension."
    end
end

# Requires ffmpeg with libvpx. 'brew reinstall ffmpeg --with-libvpx'
function webmify -d "Convert video into webm" -a video flags
    ffmpeg -i $video -vcodec libvpx -acodec libvorbis -isync -copyts -aq 80 -threads 3 -qmax 30 -y $flags $video.webm
end

function mkd -d "Create a new directory and enter it" -a name
    mkdir -p $name && cd "$_"
end

function timed -d "Time a command"
    begin
        time fish -c "$argv"
    end 2>&1
end

# Short for `cdfinder`
function cdf -d "Change working directory to the top-most Finder window location"
    cd (osascript -e 'tell app "Finder" to POSIX path of (insertion location as alias)')
end

function fs -d "Determine size of a file or total size of a directory"
    if du -b /dev/null >/dev/null 2>&1
        set -l arg -sbh
    else
        set -l arg -sh
    end

    if test -n "$argv"
        du $arg -- "$argv"
    else
        du $arg .[^.]* ./*
    end
end

function dataurl -d "Create a data URL from a file" -a file
    set -l mimeType (file -b --mime-type "$file")
    if string match -q -- "text/*" $mimeType
        set -l mimeType "$mimeType;charset=utf-8"
    end
    echo "data:$mimeType;base64,"(openssl base64 -in "$file" | tr -d '\n')
end

function digga -d "Run 'dig' and display the most useful info" -a host
    dig +nocmd "$host" any +multiline +noall +answer
end

function getcertnames -d "Show all the names (CNs and SANs) listed in the SSL certificate for a given domain" -a domain
    if test -z "$domain"
        echo "ERROR: No domain specified."
        return 1
    end

    echo "Testing $domain…"
    echo ""
    # newline

    set -l tmp (echo -e "GET / HTTP/1.0\nEOT" \
		| openssl s_client -connect "$domain:443" -servername "$domain" 2>&1)

    if string match -q -- "*-----BEGIN CERTIFICATE-----*" $tmp
        set -l certText (echo "$tmp" \
			| openssl x509 -text -certopt "no_aux, no_header, no_issuer, no_pubkey, \
			no_serial, no_sigdump, no_signame, no_validity, no_version")
        echo "Common Name:"
        echo "" # newline
        echo "$certText" | grep "Subject:" | sed -e "s/^.*CN=//" | sed -e "s/\/emailAddress=.*//"
        echo "" # newline
        echo "Subject Alternative Name(s):"
        echo "" # newline
        echo "$certText" | grep -A 1 "Subject Alternative Name:" \
            | sed -e "2s/DNS://g" -e "s/ //g" | tr "," "\n" | tail -n +2
        return 0
    else
        echo "ERROR: Certificate not found."
        return 1
    end
end

# Normalize `open` across Linux, macOS, and Windows.
# This is needed to make the `o` function (see below) cross-platform.
if not test (uname -s) = Darwin
    if grep -q Microsoft /proc/version 2>/dev/null
        # Ubuntu on Windows using the Linux subsystem
        alias open='explorer.exe'
    else
        alias open='xdg-open'
    end
end

function o -d "Opens the current directory, otherwise opens the given location"
    if test (count $argv) -eq 0
        open .
    else
        open "$argv"
    end
end

# `tre` is a shorthand for `tree` with hidden files and color enabled, ignoring
# the `.git` directory, listing directories first. The output gets piped into
# `less` with options to preserve color and line numbers, unless the output is
# small enough for one screen.
function tre -d "tree with hidden files, color enabled, ignoring .git and node_modules"
    tree -aC -I '.git|node_modules' --dirsfirst "$argv" | less -FRNX
end

# Extract archives - use: extract <file>
# Based on http://dotfiles.org/~pseup/.bashrc
function extract -d "Extract archives" -a file
    if test -f $file
        set -l filename (basename "$file")
        set -l foldername (dirname "$file")
        set -l fullpath (perl -e 'use Cwd "abs_path";print abs_path(shift)' "$file")
        set -l didfolderexist false
        if test -d "$foldername"
            set -l didfolderexist true
            read -p "$foldername already exists, do you want to overwrite it? (Y/n) " -n 1
            echo
            if string match -qr '^[Nn]$' -- $REPLY
                return
            end
        end
        mkdir -p "$foldername"; and cd "$foldername"
        switch $file
            case *.tar.bz2
                tar xjf "$fullpath"
            case *.tar.gz
                tar xzf "$fullpath"
            case *.tar.xz
                tar Jxvf "$fullpath"
            case *.tar.Z
                tar xzf "$fullpath"
            case *.tar
                tar xf "$fullpath"
            case *.taz
                tar xzf "$fullpath"
            case *.tb2
                tar xjf "$fullpath"
            case *.tbz
                tar xjf "$fullpath"
            case *.tbz2
                tar xjf "$fullpath"
            case *.tgz
                tar xzf "$fullpath"
            case *.txz
                tar Jxvf "$fullpath"
            case *.zip
                unzip "$fullpath"
            case *
                echo "'$file' cannot be extracted via extract()" && cd .. && ! $didfolderexist && rm -r "$foldername"
        end
    else
        echo "'$file' is not a valid file"
    end
end

# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
function targz -d "Create a .tar.gz archive"
    set -l tmpFile (mktemp archive.XXXXX)
    tar -cvf "$tmpFile" --exclude=".DS_Store" "$argv"; or return 1

    set -l size (
		stat -f"%z" "$tmpFile" 2> /dev/null; # macOS `stat`
		stat -c"%s" "$tmpFile" 2> /dev/null;  # GNU `stat`
	)

    set -l cmd ""
    if test size -lt 52428800; and hash zopfli 2>/dev/null
        # the .tar file is smaller than 50 MB and Zopfli is available; use it
        set -l cmd zopfli
    else
        if hash pigz 2>/dev/null
            set -l cmd pigz
        else
            set -l cmd gzip
        end
    end

    echo "Compressing .tar ("(math $size / 1000)" kB) using '$cmd'…"
    $cmd -v "$tmpFile"; or return 1
    test -f "$tmpFile"; and rm "$tmpFile"

    set -l zippedSize (
		stat -f"%z" "$tmpFile.gz" 2> /dev/null; # macOS `stat`
		stat -c"%s" "$tmpFile.gz" 2> /dev/null; # GNU `stat`
	)

    echo "$tmpFile.gz ("(math $zippedSize / 1000)" kB) created successfully."
end

function random_mac
    sudo ifconfig en0 ether (openssl rand -hex 6 | sed 's%\(..\)%\1:%g; s%.$%%')
end

function ports -d "manage processes by the ports they are using"
    switch $argv[1]
        case ls
            lsof -i -n -P
        case show
            lsof -i :"$argv[2]" | tail -n 1
        case pid
            ports show "$argv[2]" | awk '{ print $2; }'
        case kill
            ports pid "$argv[2]" | kill -9
        case '*'
            echo "NAME:
  ports - a tool to easily see what's happening on your computer's ports
USAGE:
  ports [global options] command [command options] [arguments...]
COMMANDS:
  ls                list all open ports and the processes running in them
  show <port>       shows which process is running on a given port
  pid <port>        same as show, but prints only the PID
  kill <port>       kill the process is running in the given port with kill -9
GLOBAL OPTIONS:
  --help,-h         show help"
    end
end

# function docker -w docker
#     switch $argv[1]
#         case exit
#             pkill Docker
#         case prune
#             _docker_start
#             command docker system prune --volumes -fa
#         case '*'
#             _docker_start
#             command docker $argv
#     end
# end

# function _docker_start
#     switch (uname)
#         case Darwin
#             if test (pgrep com.docker.driver | wc -l) -eq 0
#                 open -g -j -a Docker.app
#                 while ! command docker stats --no-stream >/dev/null 2>&1
#                     echo -n .
#                     sleep 1
#                 end
#                 echo
#             end
#     end
# end

function localip -d "Retrieve the IP address for the currently active network interface"
	set -lx activeIf (netstat -rn | grep default | awk '{print $NF}' | head -1)
	ipconfig getifaddr "$activeIf"
end
