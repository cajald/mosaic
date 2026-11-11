IMPLEMENTATION MODULE XServer ;

FROM SYSTEM IMPORT ADR ;
FROM Xlib IMPORT XOpenDisplay, XCloseDisplay, XDefaultScreen, XRootWindow,
                 XDisplayWidth, XDisplayHeight, XDefaultVisual,
                 XDefaultColormap, XDefaultDepth, XPending, XFlush,
                 XConnectionNumber ;
FROM XGlue IMPORT Event, mx_next_event, mx_install_error_handler,
                  mx_close_im ;
FROM Posix IMPORT PollFd, POLLIN, poll ;
FROM libc IMPORT getenv ;
IMPORT Log ;

PROCEDURE Open () : BOOLEAN ;
BEGIN
  dpy := XOpenDisplay (NIL) ;
  IF dpy = NIL
  THEN
    IF getenv (ADR ("DISPLAY")) = NIL
    THEN
      Log.Error ("cannot open display: DISPLAY is not set")
    ELSE
      Log.Error ("cannot open display")
    END ;
    RETURN FALSE
  END ;
  mx_install_error_handler ;
  screen := XDefaultScreen (dpy) ;
  root := XRootWindow (dpy, screen) ;
  width := XDisplayWidth (dpy, screen) ;
  height := XDisplayHeight (dpy, screen) ;
  visual := XDefaultVisual (dpy, screen) ;
  colormap := XDefaultColormap (dpy, screen) ;
  depth := XDefaultDepth (dpy, screen) ;
  RETURN TRUE
END Open ;

PROCEDURE Close ;
BEGIN
  IF dpy # NIL
  THEN
    mx_close_im ;
    IF XCloseDisplay (dpy) = 0 THEN END ;
    dpy := NIL
  END
END Close ;

PROCEDURE WaitEvent (timeoutMs: INTEGER) : BOOLEAN ;
VAR
  pfd: PollFd ;
BEGIN
  IF XPending (dpy) > 0
  THEN
    RETURN TRUE
  END ;
  IF XFlush (dpy) = 0 THEN END ;
  pfd.fd := XConnectionNumber (dpy) ;
  pfd.events := POLLIN ;
  pfd.revents := 0 ;
  IF poll (pfd, 1, timeoutMs) > 0
  THEN
    RETURN XPending (dpy) > 0
  END ;
  RETURN FALSE
END WaitEvent ;

PROCEDURE NextEvent (VAR e: Event) : BOOLEAN ;
BEGIN
  RETURN mx_next_event (dpy, e) # 0
END NextEvent ;

BEGIN
  dpy := NIL
END XServer.
