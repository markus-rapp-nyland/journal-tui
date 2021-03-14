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
    # '\e[0;Nr':   Set scroll area from line 0 to the third last line on screen
    printf '\e[?1049h\e[?7l\e[?25l\e[2J\e[0;%sr' "$((LINES - 3))"

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

print_status_line() {
	local status_line="(0/0) Week $selected_week $selected_year"
	# '\e[%sH': 	Move cursor to specified line, in this case to the second to last line
	# '\e[30;41m':	Set red background color
	# '%*s': 	Fill the whole line with the red background color
	# '\e[m':	Reset formatting
	printf '\e[%sH\e[30;41m%*s\e[m' "$((LINES - 1))" "-$COLUMNS" "$status_line"
}

print_file() {
    # %-V Non zero padded ISO-8601 week number
    # %G Year corresponding to the ISO-8601 week number 
    local tmp_date=$(date -d "+ $week_offset weeks" '+%-V-%G')
    selected_week="${tmp_date%-*}"
    selected_year="${tmp_date#*-}"
    selected_week_file="week-${tmp_date}.txt"
    printf "$selected_week_file \n"
}

open() {
	reset_terminal
	local file=$(printf "${SAVE_LOCATION}/${year}-${month}-%02d.txt" "$line")
	if [[ ! -f $file ]]; then
		printf -- "-- %02d ${months[${month#0} - 1]} $year --" "$line" >> "$file"
	fi
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
      ((week_offset++))
      print_file
      print_status_line
    ;;
	# Left arrow or 'h'
    h|$'\e[D'|$'\eOD')
      ((week_offset--))
      print_file
      print_status_line
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
	#if [[ -z $SAVE_LOCATION ]]; then
	#	echo "Error: variable SAVE_LOCATION must be set"
	#	exit 1
	#fi

	# in later bash versions SIGWINCH does not interupt read commands
	# this causes the window to not redraw itself on window resizes
	# solution is to add a small timeout to the read so that SIGWINCH can sneak past  
	((BASH_VERSINFO[0] > 3)) &&
		extra_read_flags=(-t 0.05)

	#set int type
	typeset -i week_offset selected_week selected_year
	week_offset=0
	printf -v current_date '%(%Y-%m-%d)T'

	# Trap the SIGWINCH signal (handle window resizes)
	trap 'get_term_size; redrawScreen' WINCH
  
	# Trap the exit signal (we need to reset the terminal to a useable state.)
	trap 'reset_terminal' EXIT

	setup_terminal
	print_file
	print_status_line

	# Vintage infinite loop.
	for ((;;)); {
		read "${extra_read_flags[@]}" -srn 1 && key "$REPLY"

		# Exit if there is no longer a terminal attached.
		[[ -t 1 ]] || exit 1
	}
}

main "$@"
