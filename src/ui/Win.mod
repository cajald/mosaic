IMPLEMENTATION MODULE Win ;

FROM SYSTEM IMPORT ADR ;
FROM Xlib IMPORT Window, Atom, KeySym, XCreateSimpleWindow, XDestroyWindow,
                 XSelectInput, XSetWMProtocols, XChangeProperty,
                 PropModeReplace, XA_STRING, XA_ATOM, XA_CARDINAL, XA_WM_NAME,
                 ExposureMask, KeyPressMask, ButtonPressMask,
                 ButtonReleaseMask, PointerMotionMask, StructureNotifyMask,
                 FocusChangeMask, ClientMessage ;
FROM XGlue IMPORT Event, mx_set_override_redirect, mx_set_size_hints,
                  mx_create_ic, mx_destroy_ic, mx_lookup_key ;
FROM XServer IMPORT dpy, root ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM libc IMPORT getpid ;
IMPORT Gfx, Atoms, Props, Str ;

CONST
  WindowMask = ExposureMask + KeyPressMask + ButtonPressMask +
               ButtonReleaseMask + PointerMotionMask + StructureNotifyMask +
               FocusChangeMask ;

PROCEDURE NewHandle (w: Window; width, height: INTEGER) : Handle ;
VAR
  h: Handle ;
BEGIN
  NEW (h) ;
  h^.window := w ;
  h^.width := width ;
  h^.height := height ;
  h^.ic := NIL ;
  h^.surface := Gfx.NewSurface (w, TRUE) ;
  Gfx.Resize (h^.surface, width, height) ;
  RETURN h
END NewHandle ;

PROCEDURE SetClass (w: Window; class: ARRAY OF CHAR) ;
VAR
  data: ARRAY [0..127] OF CHAR ;
  i, n: CARDINAL ;
BEGIN
  (* "instance\0Class\0" with the class capitalised *)
  n := Str.Length (class) ;
  IF 2 * n + 2 > HIGH (data) + 1
  THEN
    RETURN
  END ;
  FOR i := 0 TO n - 1 DO
    data[i] := class[i] ;
    data[n + 1 + i] := class[i]
  END ;
  data[n] := 0C ;
  IF (data[n + 1] >= 'a') AND (data[n + 1] <= 'z')
  THEN
    data[n + 1] := CHR (ORD (data[n + 1]) - 32)
  END ;
  data[2 * n + 1] := 0C ;
  IF XChangeProperty (dpy, w, Atoms.WmClass, XA_STRING, 8, PropModeReplace,
                      ADR (data), 2 * n + 2) = 0 THEN END
END SetClass ;

PROCEDURE Create (title, class: ARRAY OF CHAR; width, height,
                  minWidth, minHeight: INTEGER) : Handle ;
VAR
  w: Window ;
  protocols: ARRAY [0..0] OF LONGCARD ;
  h: Handle ;
BEGIN
  w := XCreateSimpleWindow (dpy, root, 0, 0, width, height, 0, 0,
                            Gfx.Pixel (Gfx.Face)) ;
  IF XSelectInput (dpy, w, WindowMask) = 0 THEN END ;
  protocols[0] := Atoms.WmDeleteWindow ;
  IF XSetWMProtocols (dpy, w, ADR (protocols), 1) = 0 THEN END ;
  SetClass (w, class) ;
  Props.SetCardinal (w, Atoms.NetWmPid, XA_CARDINAL, getpid ()) ;
  mx_set_size_hints (dpy, w, minWidth, minHeight, 0, 0) ;
  h := NewHandle (w, width, height) ;
  SetTitle (h, title) ;
  h^.ic := mx_create_ic (dpy, w) ;
  RETURN h
END Create ;

PROCEDURE CreatePopup (x, y, width, height: INTEGER) : Handle ;
VAR
  w: Window ;
BEGIN
  w := XCreateSimpleWindow (dpy, root, x, y, width, height, 0, 0,
                            Gfx.Pixel (Gfx.Face)) ;
  mx_set_override_redirect (dpy, w, 1) ;
  IF XSelectInput (dpy, w, WindowMask) = 0 THEN END ;
  RETURN NewHandle (w, width, height)
END CreatePopup ;

PROCEDURE SetType (h: Handle; type: Atom) ;
BEGIN
  Props.SetCardinal (h^.window, Atoms.NetWmWindowType, XA_ATOM, type)
END SetType ;

PROCEDURE SetTitle (h: Handle; title: ARRAY OF CHAR) ;
BEGIN
  Props.SetText (h^.window, Atoms.NetWmName, title) ;
  (* legacy name for clients that only read WM_NAME *)
  Props.SetText (h^.window, XA_WM_NAME, title)
END SetTitle ;

PROCEDURE Destroy (VAR h: Handle) ;
BEGIN
  IF h = NIL
  THEN
    RETURN
  END ;
  mx_destroy_ic (h^.ic) ;
  Gfx.FreeSurface (h^.surface) ;
  IF XDestroyWindow (dpy, h^.window) = 0 THEN END ;
  DISPOSE (h) ;
  h := NIL
END Destroy ;

PROCEDURE Configured (h: Handle; VAR e: Event) : BOOLEAN ;
BEGIN
  IF (e.width = h^.width) AND (e.height = h^.height)
  THEN
    RETURN FALSE
  END ;
  h^.width := e.width ;
  h^.height := e.height ;
  Gfx.Resize (h^.surface, e.width, e.height) ;
  RETURN TRUE
END Configured ;

PROCEDURE IsClose (h: Handle; VAR e: Event) : BOOLEAN ;
BEGIN
  RETURN (e.type = ClientMessage) AND (e.window = h^.window) AND
         (e.atom = Atoms.WmProtocols) AND
         (VAL (LONGCARD, e.data[0]) = Atoms.WmDeleteWindow)
END IsClose ;

PROCEDURE Key (h: Handle; VAR e: Event; VAR sym: KeySym;
               VAR text: ARRAY OF CHAR) ;
BEGIN
  IF mx_lookup_key (h^.ic, e.raw, text, HIGH (text) + 1, sym) < 0 THEN END
END Key ;

END Win.
