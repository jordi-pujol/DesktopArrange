#!/bin/bash

Debug=""

# A rule
#
# Get the title of the new window.
rule_check_title="QEMU (BlissOS9-overlay)"

# When the window is created wait 30 seconds to apply these properties
rule_set_delay=30

# Set the X Y coordinates
rule_set_position='25%,0'
# Set the width/height
rule_set_size='73%,98%'
# add this rule to the list of rules
AddRule

# Another rule
rule_set_delay=30
# Get the title of the new window.
rule_check_title="QEMU (BlissOS9-persistent)"
# Check size for current desktop
rule_check_desktop_size="1920x1080"

# Set the X/Y coordinates of a window.
rule_set_position='50,0'
# Set the width/height of a window.
rule_set_size='1400,1050'

# add this rule to the list of rules
AddRule
