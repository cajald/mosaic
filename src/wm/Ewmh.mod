IMPLEMENTATION MODULE Ewmh ;

FROM SYSTEM IMPORT TSIZE ;
FROM Xlib IMPORT Window, Atom, None, XCreateSimpleWindow, XDestroyWindow,
                 XMapWindow, XDeleteProperty, XA_WINDOW, XA_ATOM,
                 XA_CARDINAL ;
FROM XGlue IMPORT mx_set_override_redirect ;
FROM XServer IMPORT dpy, root, width, height ;
FROM Clients IMPORT Client, AllDesktops ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
IMPORT Clients, Atoms, Props ;

CONST
  MaxDesktops = 32 ;

TYPE
  WindowList = POINTER TO ARRAY [0..65535] OF LONGCARD ;

PROCEDURE Add (VAR s: ARRAY OF LONGCARD; VAR n: CARDINAL; a: Atom) ;
BEGIN
  s[n] := a ;
  INC (n)
END Add ;

PROCEDURE Setup ;
VAR
  s: ARRAY [0..47] OF LONGCARD ;
  n: CARDINAL ;
BEGIN
  checkWindow := XCreateSimpleWindow (dpy, root, -10, -10, 1, 1, 0, 0, 0) ;
  mx_set_override_redirect (dpy, checkWindow, 1) ;
  IF XMapWindow (dpy, checkWindow) = 0 THEN END ;
  Props.SetCardinal (checkWindow, Atoms.NetSupportingWmCheck, XA_WINDOW,
                     checkWindow) ;
  Props.SetText (checkWindow, Atoms.NetWmName, "Mosaic") ;
  Props.SetCardinal (root, Atoms.NetSupportingWmCheck, XA_WINDOW,
                     checkWindow) ;
  n := 0 ;
  Add (s, n, Atoms.NetSupported) ;
  Add (s, n, Atoms.NetSupportingWmCheck) ;
  Add (s, n, Atoms.NetClientList) ;
  Add (s, n, Atoms.NetClientListStacking) ;
  Add (s, n, Atoms.NetActiveWindow) ;
  Add (s, n, Atoms.NetCloseWindow) ;
  Add (s, n, Atoms.NetWmMoveresize) ;
  Add (s, n, Atoms.NetNumberOfDesktops) ;
  Add (s, n, Atoms.NetCurrentDesktop) ;
  Add (s, n, Atoms.NetDesktopNames) ;
  Add (s, n, Atoms.NetDesktopGeometry) ;
  Add (s, n, Atoms.NetDesktopViewport) ;
  Add (s, n, Atoms.NetWorkarea) ;
  Add (s, n, Atoms.NetWmDesktop) ;
  Add (s, n, Atoms.NetWmState) ;
  Add (s, n, Atoms.NetWmStateFullscreen) ;
  Add (s, n, Atoms.NetWmStateHidden) ;
  Add (s, n, Atoms.NetWmStateMaximizedVert) ;
  Add (s, n, Atoms.NetWmStateMaximizedHorz) ;
  Add (s, n, Atoms.NetWmStateDemandsAttention) ;
  Add (s, n, Atoms.NetWmStateSkipTaskbar) ;
  Add (s, n, Atoms.NetWmStateSkipPager) ;
  Add (s, n, Atoms.NetWmName) ;
  Add (s, n, Atoms.NetWmWindowType) ;
  Add (s, n, Atoms.NetWmWindowTypeDock) ;
  Add (s, n, Atoms.NetWmWindowTypeDesktop) ;
  Add (s, n, Atoms.NetWmWindowTypeDialog) ;
  Add (s, n, Atoms.NetWmWindowTypeNormal) ;
  Add (s, n, Atoms.NetWmStrut) ;
  Add (s, n, Atoms.NetWmStrutPartial) ;
  Add (s, n, Atoms.NetFrameExtents) ;
  Add (s, n, Atoms.NetRequestFrameExtents) ;
  Props.SetCardinals (root, Atoms.NetSupported, XA_ATOM, s, n) ;
  SetActive (None) ;
  UpdateClientList
END Setup ;

PROCEDURE Teardown ;
BEGIN
  IF XDeleteProperty (dpy, root, Atoms.NetSupportingWmCheck) = 0 THEN END ;
  IF XDeleteProperty (dpy, root, Atoms.NetSupported) = 0 THEN END ;
  IF XDeleteProperty (dpy, root, Atoms.NetClientList) = 0 THEN END ;
  IF XDeleteProperty (dpy, root, Atoms.NetClientListStacking) = 0 THEN END ;
  IF XDeleteProperty (dpy, root, Atoms.NetActiveWindow) = 0 THEN END ;
  IF XDeleteProperty (dpy, root, Atoms.NetWorkarea) = 0 THEN END ;
  IF XDeleteProperty (dpy, root, Atoms.NetDesktopViewport) = 0 THEN END ;
  IF XDestroyWindow (dpy, checkWindow) = 0 THEN END
END Teardown ;

PROCEDURE UpdateClientList ;
VAR
  list: WindowList ;
  c: Client ;
  i, n: CARDINAL ;
BEGIN
  n := Clients.count ;
  IF n = 0
  THEN
    IF XDeleteProperty (dpy, root, Atoms.NetClientList) = 0 THEN END ;
    IF XDeleteProperty (dpy, root, Atoms.NetClientListStacking) = 0 THEN END ;
    RETURN
  END ;
  ALLOCATE (list, n * TSIZE (LONGCARD)) ;
  i := 0 ;
  c := Clients.first ;
  WHILE c # NIL DO
    list^[i] := c^.window ;
    INC (i) ;
    c := c^.next
  END ;
  Props.SetCardinals (root, Atoms.NetClientList, XA_WINDOW, list^, n) ;
  (* stacking list runs bottom to top *)
  i := n ;
  c := Clients.stackTop ;
  WHILE c # NIL DO
    DEC (i) ;
    list^[i] := c^.window ;
    c := c^.stackNext
  END ;
  Props.SetCardinals (root, Atoms.NetClientListStacking, XA_WINDOW, list^, n) ;
  DEALLOCATE (list, n * TSIZE (LONGCARD))
END UpdateClientList ;

PROCEDURE SetActive (w: Window) ;
BEGIN
  Props.SetCardinal (root, Atoms.NetActiveWindow, XA_WINDOW, w)
END SetActive ;

PROCEDURE SetDesktops (count, current: INTEGER) ;
VAR
  v: ARRAY [0..1] OF LONGCARD ;
BEGIN
  Props.SetCardinal (root, Atoms.NetNumberOfDesktops, XA_CARDINAL, count) ;
  Props.SetCardinal (root, Atoms.NetCurrentDesktop, XA_CARDINAL, current) ;
  v[0] := width ;
  v[1] := height ;
  Props.SetCardinals (root, Atoms.NetDesktopGeometry, XA_CARDINAL, v, 2)
END SetDesktops ;

PROCEDURE SetWorkarea (desktops, x, y, width, height: INTEGER) ;
VAR
  v: ARRAY [0..4 * MaxDesktops - 1] OF LONGCARD ;
  vp: ARRAY [0..2 * MaxDesktops - 1] OF LONGCARD ;
  i: INTEGER ;
BEGIN
  FOR i := 0 TO desktops - 1 DO
    v[4 * i] := x ;
    v[4 * i + 1] := y ;
    v[4 * i + 2] := width ;
    v[4 * i + 3] := height ;
    vp[2 * i] := 0 ;
    vp[2 * i + 1] := 0
  END ;
  Props.SetCardinals (root, Atoms.NetWorkarea, XA_CARDINAL, v, 4 * desktops) ;
  Props.SetCardinals (root, Atoms.NetDesktopViewport, XA_CARDINAL, vp,
                      2 * desktops)
END SetWorkarea ;

PROCEDURE SetClientDesktop (c: Client) ;
BEGIN
  IF c^.desktop = AllDesktops
  THEN
    Props.SetCardinal (c^.window, Atoms.NetWmDesktop, XA_CARDINAL,
                       0FFFFFFFFH)
  ELSE
    Props.SetCardinal (c^.window, Atoms.NetWmDesktop, XA_CARDINAL,
                       c^.desktop)
  END
END SetClientDesktop ;

PROCEDURE SetClientState (c: Client) ;
VAR
  s: ARRAY [0..7] OF LONGCARD ;
  n: CARDINAL ;
BEGIN
  n := 0 ;
  IF c^.fullscreen THEN s[n] := Atoms.NetWmStateFullscreen ; INC (n) END ;
  IF c^.minimized THEN s[n] := Atoms.NetWmStateHidden ; INC (n) END ;
  IF c^.maximized
  THEN
    s[n] := Atoms.NetWmStateMaximizedVert ; INC (n) ;
    s[n] := Atoms.NetWmStateMaximizedHorz ; INC (n)
  END ;
  IF c^.urgent THEN s[n] := Atoms.NetWmStateDemandsAttention ; INC (n) END ;
  IF c^.skipTaskbar THEN s[n] := Atoms.NetWmStateSkipTaskbar ; INC (n) END ;
  IF c^.skipPager THEN s[n] := Atoms.NetWmStateSkipPager ; INC (n) END ;
  Props.SetCardinals (c^.window, Atoms.NetWmState, XA_ATOM, s, n)
END SetClientState ;

(* ewmh: a withdrawn window loses its desktop and state *)
PROCEDURE ClearClient (c: Client) ;
BEGIN
  IF XDeleteProperty (dpy, c^.window, Atoms.NetWmDesktop) = 0 THEN END ;
  IF XDeleteProperty (dpy, c^.window, Atoms.NetWmState) = 0 THEN END
END ClearClient ;

BEGIN
  checkWindow := None
END Ewmh.
