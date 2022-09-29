#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.11 $
#
#  Copyright (C) 2022-2022 Jordi Pujol <jordipujolp AT gmail DOT com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3, or (at your option)
#  any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#************************************************************************

# Daemon setup
# empty string (default), y|verbose, xtrace
Debug=""
#Debug="verbose"
#Debug="xtrace"

# A window definition
#
# Title of the window.
rule_check_title="title"
# Type of the window.
rule_check_type="WINDOW_NORMAL", "WINDOW_TOOLBAR", etc.
# Application which created the window.
rule_check_application="/usr/bin/qemu"
# Class of the window.
rule_check_class="QEMU"
# Get the role of the new window, via WM_WINDOW_ROLE.
# This may return an empty string.
rule_check_role=""
# Get the workspace the window is active on.
# The return value may be -1 if the window is pinned, or invisible.
rule_check_desktop="0..(n-1)"
# Is the window focussed?
rule_check_is_focussed=
# Is the window maximized?
rule_check_is_maximized=
# Is the window fullscreen?
rule_check_is_fullscreen=
# Check size for current desktop
rule_check_desktop_size="1920x1080"
# Check workarea for current desktop
rule_check_desktop_workarea="1920x1080"

## Get the position of the mouse pointer.
#get_pointer=
## Depth ##

# When the window is created wait 30 seconds to apply these properties
rule_set_delay=30
# Make the window appear in the foreground and give focus.
rule_set_active="y|yes|enable|true|1"
# Make the window "always on top" when value is "y".
# Remove the "always on top" flag when value is "n".
rule_set_above="y|yes|enable|true|1  n|no|disable|false|0"
# Make the window "always below" when value is "y".
# Remove the "always below" flag when value is "n".
rule_set_bottom=
## Max/Min ##
# Maximize the window.
rule_set_maximized="y|yes|enable|true|1  n|no|disable|false|0"
# Maximize horizontally.
rule_set_maximized_horizontally="y|yes|enable|true|1  n|no|disable|false|0"
# Maximize vertically.
rule_set_maximized_vertically="y|yes|enable|true|1  n|no|disable|false|0"
# Make the window "fullscreen".
rule_set_fullscreen="y|yes|enable|true|1  n|no|disable|false|0"
# Focus the window and change to the desktop that contains this window.
rule_set_focus="y|yes|enable|true|1"
# Minimize the window.
rule_set_minimized="y|yes|enable|true|1"
## Workspace ##
# Pin on all workspaces when value is "y".
# Don't pin on all workspaces when value is "n".
rule_set_pin="y|yes|enable|true|1  n|no|disable|false|0"
## Movement ##
# Set the X/Y coordinates of a window.
rule_set_position="400|20%|x,200|10%|y"
# Set the width/height of a window.
rule_set_size="400|20%|x,200|10%|y"
## Workspaces ##
# Change to the given workspace/virtual-desktop.
rule_set_active_desktop="0..(n-1)"
# Set the workspace the window is active on.
rule_set_desktop="0..(n-1)"
## Misc ##
# Set/Unset the decorations for the window.
rule_set_decoration="y|yes|enable|true|1  n|no|disable|false|0"
# Close the window, forcibly.
rule_set_killed="y|yes|enable|true|1"
# Set the position of the mouse pointer.
rule_set_pointer="400|20%|x,200|10%|y"
# add this rule to the list of rules
AddRule
