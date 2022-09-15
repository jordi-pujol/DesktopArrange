#!/bin/bash

Debug=""

# A window definition
#
# When the window is created wait 30 seconds to apply these properties
window_get_delay=30
# Title of the new window.
window_get_title="QEMU (BlissOS9-overlay)"
# Set the X coordinate of a window and leave Y untouched.
window_set_position='500,y'
# Set the width/height of a window.
window_set_size='1400,y'
#window_set_maximized="y"
#window_set_maximized_horizontally="y"
window_set_maximized_vertically="y"
# add this window definition to the list of windows
AddWindow

# Another window definition
window_get_delay=30
# Get the title of the new window.
window_get_title="QEMU (BlissOS9-persistent)"
# Set the X/Y coordinates of a window.
window_set_position='50,0'
# Set the width/height of a window.
window_set_size='1400,1050'
AddWindow