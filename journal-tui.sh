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

get_file() {
    # %-V Non zero padded ISO-8601 week number
    # %G Year corresponding to the ISO-8601 week number 
    # shellcheck disable=SC2155
    local tmp_date=$(date -d "+ $week_offset weeks" '+%-V-%G')
    selected_week="${tmp_date%-*}"
    selected_year="${tmp_date#*-}"
    selected_file="${SAVE_LOCATION}/week-${tmp_date}.txt"
    if [[ -f $selected_file ]]; then
        mapfile -t file_array < "$selected_file"
    else
        file_array=()
    fi
	lines_in_file="${#file_array[@]}"
}

print_file() {
	if [[ $lines_in_file -eq 0 ]]; then
		printf "No notes for this week yet, press 'enter' to create one"
		first_line_on_screen=0
		last_line_on_screen=0
	else
	first_line_on_screen="$((1 + line_offset))"
	scroll_end="$((LINES - 3 < 0 ? 0 : LINES -3 ))" #move out for performance
	last_line_on_screen="$((line_offset + scroll_end < lines_in_file ? line_offset + scroll_end : lines_in_file))"
	# Print each line in scroll area
	for ((i=0;i<scroll_end;i++)); {
		printf '\e[%iH%s' "$((i + 1))" "${file_array[((i + line_offset))]}"
	}
	fi
}

print_status_line() {
	local status_line=" (${first_line_on_screen}/${last_line_on_screen}:${lines_in_file}) Week $selected_week $selected_year"
	# '\e[%sH': 	Move cursor to specified line, in this case to the second to last line
	# '\e[30;41m':	Set red background color
	# '%*s': 	Fill the whole line with the red background color
	# '\e[m':	Reset formatting
	printf '\e[%sH\e[30;41m%*s\e[m' "$((LINES - 1))" "-$COLUMNS" "$status_line"
}

redraw_screen() {
	# Clear the screen and move cursor to (0,0)
	printf '\e[2J\e[H'
	print_file
	print_status_line
}

open() {
    reset_terminal
    vim "$selected_file"
    setup_terminal
    get_file
    print_file
    print_status_line
}

key()  {
  # Handle special key presses
  if [[ $1 == $'\e' ]]; then
	read -rsn 2
	local special_key="${1}${REPLY}"
  fi

  case "${special_key:-$1}" in
	# Right arrow or 'l'
	l|$'\e[C'|$'\eOC')
		((week_offset++))
		get_file
		redraw_screen
	;;
	# Left arrow or 'h'
	h|$'\e[D'|$'\eOD')
		((week_offset--))
		get_file
		redraw_screen
	;;
	# Down arrow or 'j'
	j|$'\e[B'|$'\e[OB')
		# Only scroll down if more content below
		if (( line_offset + scroll_end < lines_in_file )); then
			((line_offset++))
			redraw_screen
		fi
	;;
	# Up arrow or 'k'
	k|$'\e[A'|$'\e[OA')
		# Only scroll up if more content above
		if [[ $line_offset -ne 0 ]]; then
			((line_offset--))
			redraw_screen
		fi
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
	# require SAVE_LOCATION to be set
	if [[ -z $SAVE_LOCATION ]]; then
		echo "Error: variable SAVE_LOCATION must be set"
		exit 1
	fi

	# in later bash versions SIGWINCH does not interrupt read commands
	# this causes the window to not redraw itself on window resizes
	# solution is to add a small timeout to the read so that SIGWINCH can sneak past  
	((BASH_VERSINFO[0] > 3)) &&
		extra_read_flags=(-t 0.05)

	#set int type
	typeset -i line_offset week_offset selected_week selected_year
	line_offset=0
	week_offset=0

	# Trap the SIGWINCH signal (handle window resizes)
	trap 'get_term_size; redraw_screen' WINCH
  
	# Trap the exit signal (resets the terminal to a usable state.)
	trap 'reset_terminal' EXIT

	get_term_size
	setup_terminal
	get_file
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
