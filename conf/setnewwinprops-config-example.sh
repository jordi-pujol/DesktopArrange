Parameters {
	#Debug=""
	debug="verbose"
}

Rule {
	check_class="qemu"
	# Continue checking and apply other rules also
	check_continue='y'
	# Move immediately this window to the desktop num 3
	set_desktop=3
	# Change to desktop num 3
	set_active_desktop=3
	# Force to focus
	set_focus='y'   
	# Undecorate.
	set_decorated='n'
}

Rule {
	# Compare the title of the new window with this string.
	check_title="QEMU (BlissOS9-overlay)"

	# Move immediately this window to the desktop num 3
	#set_desktop=3
	# Wait 30 seconds to apply the following properties
	set_delay=30
	# After waiting (delay) seconds Change to desktop num 3
	#set_active_desktop=3
	# Next, when the window is focused, set up the following properties:
	# Set the X Y coordinates
	set_position='25%,0'
	# Set the width/height
	set_size='73%,96%'
	# Undecorate.
	#set_decorated='n'
}

rule {
	set_delay=30
	# Get the title of the new window.
	check_title="QEMU (BlissOS9-persistent)"
	# Check size for current desktop
	check_desktop_size="1920x1080"

	# Set the X/Y coordinates of a window.
	set_position='50,0'
	# Set the width/height of a window.
	set_size='1400,1050'
	# Undecorate.
	set_decorated='n'
	# Wait 30 seconds to apply the following properties
	set_delay=30
	# Move this window to the desktop num 3
	set_desktop=3
	# decorate.
	set_decorated='y'
	# After waiting (delay) seconds Change to desktop num 3
	set_active_desktop=3
	# Wait 30 seconds to apply the following properties
	set_delay=10
	# After waiting (delay) seconds Change to desktop num 3
	set_active_desktop=1
	# Move this window to the desktop num 3
	set_desktop=1
	# Undecorate.
	set_decorated='n'
	# Wait 30 seconds to apply the following properties
	set_delay=10
	# Move this window to the desktop num 3
	set_desktop=3
	# decorate.
	set_decorated='y'
}

