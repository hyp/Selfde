# Selfde

A library that allows processes to debug themselves.

This library works on x86_64 OS X only.
It includes a builtin debug server that's partially based on the open source
LLDB debug server. It includes some of the code from LLDB's debug server,
like the code that defines machine register information.
The debug server is compatible with the GDB/LLDB remote debugging protocol and
supports a couple of LLDB extensions.

