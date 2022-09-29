# SetNewWinProps

*setnewwinprops* is a tool to setup properties of new opened windows.
Consists of a daemon program that runs for every X session. Works in most Linux window managers.
Each user must customize their own configuration.

*setnewwinprops* may be automatically started in an X session
by a desktop entry placed in the **~/.config/autostart** directory
and also the user may issue a command in the same X session
to start, stop or restart the daemon;
the user also may reload the configuration.
