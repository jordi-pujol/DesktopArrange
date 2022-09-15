#

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for selected opening windows
#
#  $Revision: 0.1 $
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
#
Debug=""
LogRotate=3

# A window definition
#
# Get the title of the new window.
window_get_title=
# Get the type of the window.
window_get_type="WINDOW_NORMAL", "WINDOW_TOOLBAR", etc.
# Get the application which created the window.
window_get_application=
# Get the class of the new window.
window_get_class=
# Get the ID of the new window. This may be empty.
window_get_id=
# Get the XID of the new window. This may be empty.
window_get_xid=
# Get the PID of the new window. This may be zero on error.
window_get_pid=
# Get the role of the new window, via WM_WINDOW_ROLE.
# This may return an empty string.
window_get_role=
# Get the workspace the window is active on.
# The return value may be -1 if the window is pinned, or invisible.
window_get_workspace=
# Is the window focussed?
window_is_focussed=
# Is the window maximized?
window_is_maximized=
# Is the window fullscreen?
window_is_fullscreen=
## Get the position of the mouse pointer.
#get_pointer=
## Depth ##
# Make the window appear in the foreground and give focus.
window_set_active=
# Make the window "always on top" when value is "y".
# Remove the "always on top" flag when value is "n".
window_set_above=
# Make the window "always below" when value is "y".
# Remove the "always below" flag when value is "n".
window_set_bottom=
## Max/Min ##
# Maximize the window.
window_set_maximized=
# Maximize horizontally.
window_set_maximized_horizontally=
# Maximize vertically.
window_set_maximized_vertically=
# Make the window "fullscreen".
window_set_fullscreen=
# Focus the window.
window_set_focus=
# Minimize the window.
window_set_minimized=
## Workspace ##
# Pin on all workspaces when value is "y".
# Don't pin on all workspaces when value is "n".
window_set_pin=
## Movement ##
# Set the X/Y coordinates of a window.
window_set_position=
# Set the width/height of a window.
window_set_size=
## Workspaces ##
# Change to the given workspace/virtual-desktop.
window_set_active_desktop=
# Set the workspace the window is active on.
window_set_desktop=
## Misc ##
# Set/Unset the decorations for the window.
window_set_decoration=
# Close the window, forcibly.
window_set_killed=
# Set the position of the mouse pointer.
window_set_pointer=
AddWindow
