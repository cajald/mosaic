IMPLEMENTATION MODULE Frames ;

FROM Xlib IMPORT XCreateSimpleWindow, XDestroyWindow, XReparentWindow,
                 XSelectInput, XAddToSaveSet, XRemoveFromSaveSet,
                 XMoveResizeWindow, XSetWindowBackground, XClearWindow,
                 XSetWindowBorderWidth, XMapWindow, XA_CARDINAL,
                 SubstructureRedirectMask, SubstructureNotifyMask,
                 ButtonPressMask, ButtonReleaseMask, ExposureMask ;
FROM XGlue IMPORT mx_send_configure_notify ;
FROM XServer IMPORT dpy, root ;
FROM Clients IMPORT Client ;
IMPORT Props, Atoms ;

CONST
  FrameMask = SubstructureRedirectMask + SubstructureNotifyMask +
              ButtonPressMask + ButtonReleaseMask + ExposureMask ;
  MinWidth = 32 ;
  MinHeight = 16 ;

PROCEDURE HasDecor (c: Client) : BOOLEAN ;
BEGIN
  RETURN c^.decorated AND NOT c^.fullscreen
END HasDecor ;

PROCEDURE Left (c: Client) : INTEGER ;
BEGIN
  IF HasDecor (c) THEN RETURN Border END ;
  RETURN 0
END Left ;

PROCEDURE Top (c: Client) : INTEGER ;
BEGIN
  IF HasDecor (c) THEN RETURN Border + TitleHeight END ;
  RETURN 0
END Top ;

PROCEDURE ExtraWidth (c: Client) : INTEGER ;
BEGIN
  RETURN 2 * Left (c)
END ExtraWidth ;

PROCEDURE ExtraHeight (c: Client) : INTEGER ;
BEGIN
  IF HasDecor (c) THEN RETURN 2 * Border + TitleHeight END ;
  RETURN 0
END ExtraHeight ;

PROCEDURE Create (c: Client) ;
BEGIN
  c^.frame := XCreateSimpleWindow (dpy, root, c^.x, c^.y,
                                   c^.width + ExtraWidth (c),
                                   c^.height + ExtraHeight (c), 0, 0, 0) ;
  IF XSelectInput (dpy, c^.frame, FrameMask) = 0 THEN END ;
  IF XSetWindowBorderWidth (dpy, c^.window, 0) = 0 THEN END ;
  IF XAddToSaveSet (dpy, c^.window) = 0 THEN END ;
  IF XReparentWindow (dpy, c^.window, c^.frame, Left (c), Top (c)) = 0 THEN END ;
  IF XMapWindow (dpy, c^.window) = 0 THEN END ;
  SetExtents (c)
END Create ;

PROCEDURE Release (c: Client; clientAlive: BOOLEAN) ;
BEGIN
  IF clientAlive
  THEN
    IF XReparentWindow (dpy, c^.window, root, c^.x + Left (c),
                        c^.y + Top (c)) = 0 THEN END ;
    IF XRemoveFromSaveSet (dpy, c^.window) = 0 THEN END
  END ;
  IF XDestroyWindow (dpy, c^.frame) = 0 THEN END
END Release ;

PROCEDURE Apply (c: Client) ;
BEGIN
  IF XMoveResizeWindow (dpy, c^.frame, c^.x, c^.y,
                        c^.width + ExtraWidth (c),
                        c^.height + ExtraHeight (c)) = 0 THEN END ;
  IF XMoveResizeWindow (dpy, c^.window, Left (c), Top (c),
                        c^.width, c^.height) = 0 THEN END ;
  mx_send_configure_notify (dpy, c^.window, c^.x + Left (c), c^.y + Top (c),
                            c^.width, c^.height)
END Apply ;

PROCEDURE Constrain (c: Client; VAR width, height: INTEGER) ;
BEGIN
  IF c^.incWidth > 1
  THEN
    width := c^.baseWidth + (width - c^.baseWidth) DIV c^.incWidth * c^.incWidth
  END ;
  IF c^.incHeight > 1
  THEN
    height := c^.baseHeight +
              (height - c^.baseHeight) DIV c^.incHeight * c^.incHeight
  END ;
  IF (c^.maxWidth > 0) AND (width > c^.maxWidth) THEN width := c^.maxWidth END ;
  IF (c^.maxHeight > 0) AND (height > c^.maxHeight) THEN height := c^.maxHeight END ;
  IF width < c^.minWidth THEN width := c^.minWidth END ;
  IF height < c^.minHeight THEN height := c^.minHeight END ;
  IF width < MinWidth THEN width := MinWidth END ;
  IF height < MinHeight THEN height := MinHeight END
END Constrain ;

PROCEDURE Draw (c: Client; active: BOOLEAN) ;
BEGIN
  IF active
  THEN
    IF XSetWindowBackground (dpy, c^.frame, 03A5A78H) = 0 THEN END
  ELSE
    IF XSetWindowBackground (dpy, c^.frame, 0A0A0A0H) = 0 THEN END
  END ;
  IF XClearWindow (dpy, c^.frame) = 0 THEN END
END Draw ;

PROCEDURE SetExtents (c: Client) ;
VAR
  e: ARRAY [0..3] OF LONGCARD ;
BEGIN
  e[0] := Left (c) ;
  e[1] := Left (c) ;
  e[2] := Top (c) ;
  e[3] := ExtraHeight (c) - Top (c) ;
  Props.SetCardinals (c^.window, Atoms.NetFrameExtents, XA_CARDINAL, e, 4)
END SetExtents ;

END Frames.
