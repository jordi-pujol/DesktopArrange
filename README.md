# SetNewWinProps

*setnewwinprops* is a tool to setup properties of the new opened windows.
Consists of a daemon program that runs for every X session. Works in most Linux window managers.
Each user must customize their own configuration.

In an X session *setnewwinprops* may be automatically started 
by a desktop file placed in the **~/.config/autostart** directory
and also the user may start, stop, restart the daemon
or reload the configuration issuing a command in the same X session.
