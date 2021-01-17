#!/usr/bin/env bash

get_term_size() {
    # Get terminal size ('stty' is POSIX and always available).
    # This can't be done reliably across all bash versions in pure bash.
    read -r LINES COLUMNS < <(stty size)
}

setup_terminal() {
    # Setup the terminal for the TUI.
    # '\e[?1049h': Use alternative screen buffer.
    # '\e[?7l':    Disable line wrapping.
    # '\e[?25l':   Hide the cursor.
    # '\e[2J':     Clear the screen.
	# '\e[H':      Move cursor to 0,0
    printf '\e[?1049h\e[?7l\e[?25l\e[2J\e[H'

    # Hide echoing of user input
    stty -echo
}

reset_terminal() {
    # Reset the terminal to a useable state (undo all changes).
    # '\e[?7h':   Re-enable line wrapping.
    # '\e[?25h':  Unhide the cursor.
    # '\e[2J':    Clear the terminal.
	# '\e[H':     Move cursor to 0,0
    # '\e[?1049l: Restore main screen buffer.
    printf '\e[?7h\e[?25h\e[2J\e[H\e[?1049l'

    # Show user input.
    stty echo
}

extractMonthInfo() {
	local date=$(date -d "${current_date%-*}-01 + $((1 + $offset)) month -1 day" '+%Y-%m-%d')
	
	daysInMonth="${date##*-}"
	local tmp="${date#*-}"
	month="${tmp%-*}"
	year="${date%%-*}"
	
	if ((line > daysInMonth)); then
		line=daysInMonth
	fi
}

months=(January February Mars April May June July August September October November Desember)

printDates() {
	# remove leading 0 before aritmetric operation. Contant would otherwise be interpreted as an octal number.
	echo "--- ${months[${month#0} - 1]} $year ---"
  
	for ((day=1;day<=daysInMonth;day++)); do
		if ((day == line)); then
			printf "\e[100m${year}-${month}-%02d\e[0m\n" "$day"
		else
			printf "${year}-${month}-%02d\n" "$day"
		fi
	done
	
	printf "\e[%s;0H" $((line+1))
}

redrawScreen() {
	# Clear the screen and move cursor to (0,0).
    # This mimics the 'clear' command.
    printf '\e[2J\e[H'
	extractMonthInfo
	printDates
}

moveSelectionDown() {
	if ((line < daysInMonth)); then
		printf "\e[%d;0H${year}-${month}-%02d" $((line+1)) "$line"
		((line++))
		printf "\e[%d;0H\e[100m${year}-${month}-%02d\e[0m" $((line+1)) "$line"
	fi
}

moveSelectionUp() {
	if ((line > 1)); then
		printf "\e[%d;0H${year}-${month}-%02d" $((line+1)) "$line"
		((line--))
		printf "\e[%d;0H\e[100m${year}-${month}-%02d\e[0m" $((line+1)) "$line"
	fi
}

open() {
	reset_terminal
	local file=$(printf "${SAVE_LOCATION}/${year}-${month}-%02d.txt" "$line")
	vim "$file"
	setup_terminal
	redrawScreen
}

key()  {
  # Handle special key presses
  if [[ $1 == $'\e' ]]; then
	read "${read_flags[@]}" -rsn 2 
	local special_key="${1}${REPLY}"
  fi

  case "${special_key:-$1}" in
	# Right arrow or 'l'
    l|$'\e[C'|$'\eOC')
      ((offset++))
      redrawScreen
    ;;
	# Left arrow or 'h'
    h|$'\e[D'|$'\eOD')
      ((offset--))
      redrawScreen
    ;;
	# Down arrow or 'j'
	j|$'\e[B'|$'\e[OB')
		moveSelectionDown
    ;;
	# Up arrow or 'k'
	k|$'\e[A'|$'\e[OA')
		moveSelectionUp
    ;;
	# Enter
	'')
		open
	;;
    q)
      exit
    ;;
  esac
}

main() {
	# require SAVE_LOCATION to be sets
	if [[ -z $SAVE_LOCATION ]]; then
		echo "Error: variable SAVE_LOCATION must be set"
		exit 1
	fi

	# in later bash versions SIGWINCH does not interupt read commands
	# this causes the window to not redraw itself on window resizes
	# solution is to add a small timeout to the read so that SIGWINCH can sneak past  
	((BASH_VERSINFO[0] > 3)) &&
		extra_read_flags=(-t 0.05)

	typeset -i line offset
	offset=0
	current_date=$(date '+%Y-%m-%d')
	line="${current_date##*-}"

	# Trap the SIGWINCH signal (handle window resizes)
	trap 'get_term_size; redrawScreen' WINCH
  
	# Trap the exit signal (we need to reset the terminal to a useable state.)
	trap 'reset_terminal' EXIT

	setup_terminal
	redrawScreen

	# Vintage infinite loop.
	for ((;;)); {
		read "${extra_read_flags[@]}" -srn 1 && key "$REPLY"

		# Exit if there is no longer a terminal attached.
		[[ -t 1 ]] || exit 1
	}
}

main "$@"
