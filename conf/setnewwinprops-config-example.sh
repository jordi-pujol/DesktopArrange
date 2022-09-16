#!/bin/bash

Debug=""

# A rule
#
# When the window is created wait 30 seconds to apply these properties
rule_met_delay=30
# Get the title of the new window.
rule_met_title="QEMU (BlissOS9-overlay)"
# Check size for current desktop
rule_met_desktop_size="1920x1080"

# Set the X coordinate of a window and leave Y.
rule_set_position='500,y'
# Set the width/height of a window.
rule_set_size='1400,y'
#rule_set_maximized="y"
#rule_set_maximized_horizontally="y"
rule_set_maximized_vertically="yes"
# add this rule to the list of rules
AddRule

# Another rule
rule_met_delay=30
# Get the title of the new window.
rule_met_title="QEMU (BlissOS9-persistent)"
# Set the X/Y coordinates of a window.
rule_set_position='50,0'
# Set the width/height of a window.
rule_set_size='1400,1050'
AddRule

