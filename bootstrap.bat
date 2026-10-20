fxc fxc.fx
build\fxc\fxc fxc.fx -o fxc2.exe
build\fxc2\fxc2 fxc.fx -o fxc3.exe
build\fxc3\fxc3 fxc.fx -o fxc.exe
copy build\fxc\fxc.exe fxc.exe