IMPLEMENTATION MODULE Tasks ;

FROM Xlib IMPORT Window, Atom, None, PropertyChangeMask, XGetTransientForHint,
                 SubstructureNotifyMask, SubstructureRedirectMask,
                 PropertyNotify, IconicState, XA_WINDOW, XA_ATOM,
                 XA_CARDINAL, XA_WM_NAME ;
FROM XGlue IMPORT Event, mx_send_client_message, mx_add_input ;
FROM XServer IMPORT dpy, root ;
IMPORT Atoms, Props, Str ;

CONST
  RootMask = SubstructureNotifyMask + SubstructureRedirectMask ;
  SourcePager = 2 ;
  Toggle = 2 ;

VAR
  owner: Window ;
  list: ARRAY [0..MaxTasks - 1] OF LONGCARD ;

PROCEDURE ReadState (VAR t: Task) ;
VAR
  states: ARRAY [0..15] OF LONGCARD ;
  n, i: CARDINAL ;
BEGIN
  t.minimized := FALSE ;
  t.urgent := FALSE ;
  t.skip := FALSE ;
  n := Props.GetCardinals (t.window, Atoms.NetWmState, XA_ATOM, states) ;
  FOR i := 1 TO n DO
    IF states[i - 1] = Atoms.NetWmStateHidden THEN t.minimized := TRUE END ;
    IF states[i - 1] = Atoms.NetWmStateSkipTaskbar THEN t.skip := TRUE END ;
    IF states[i - 1] = Atoms.NetWmStateDemandsAttention THEN t.urgent := TRUE END
  END
END ReadState ;

PROCEDURE ReadDesktop (VAR t: Task) ;
VAR
  d: LONGCARD ;
BEGIN
  t.desktop := 0 ;
  IF Props.GetCardinal (t.window, Atoms.NetWmDesktop, XA_CARDINAL, d)
  THEN
    IF d = 0FFFFFFFFH
    THEN
      t.desktop := AllDesktops
    ELSIF d < MaxDesktops
    THEN
      t.desktop := VAL (INTEGER, d)
    END
  END
END ReadDesktop ;

PROCEDURE ReadTitle (VAR t: Task) ;
BEGIN
  IF (NOT Props.GetTitle (t.window, t.title)) OR (t.title[0] = 0C)
  THEN
    IF NOT Str.Assign ("(untitled)", t.title) THEN END
  END
END ReadTitle ;

(* docks, desktop windows and dialogs never get a task button *)
PROCEDURE Ignored (w: Window) : BOOLEAN ;
VAR
  types: ARRAY [0..7] OF LONGCARD ;
  n, i: CARDINAL ;
  parent: Window ;
BEGIN
  IF (w = owner) OR (XGetTransientForHint (dpy, w, parent) # 0)
  THEN
    RETURN TRUE
  END ;
  n := Props.GetCardinals (w, Atoms.NetWmWindowType, XA_ATOM, types) ;
  FOR i := 1 TO n DO
    IF (types[i - 1] = Atoms.NetWmWindowTypeDock) OR
       (types[i - 1] = Atoms.NetWmWindowTypeDesktop)
    THEN
      RETURN TRUE
    END
  END ;
  RETURN FALSE
END Ignored ;

PROCEDURE Find (w: Window) : INTEGER ;
VAR
  i: INTEGER ;
BEGIN
  FOR i := 0 TO count - 1 DO
    IF tasks[i].window = w
    THEN
      RETURN i
    END
  END ;
  RETURN -1
END Find ;

PROCEDURE ReadClientList ;
VAR
  n, i: CARDINAL ;
  old: INTEGER ;
  next: ARRAY [0..MaxTasks - 1] OF Task ;
  m: INTEGER ;
BEGIN
  n := Props.GetCardinals (root, Atoms.NetClientList, XA_WINDOW, list) ;
  m := 0 ;
  FOR i := 1 TO n DO
    old := Find (list[i - 1]) ;
    IF old >= 0
    THEN
      next[m] := tasks[old] ;
      INC (m)
    ELSIF NOT Ignored (list[i - 1])
    THEN
      next[m].window := list[i - 1] ;
      (* follow title, state and desktop changes; our own dialogs keep
         the events they already select *)
      mx_add_input (dpy, list[i - 1], PropertyChangeMask) ;
      ReadTitle (next[m]) ;
      ReadDesktop (next[m]) ;
      ReadState (next[m]) ;
      INC (m)
    END
  END ;
  FOR i := 1 TO VAL (CARDINAL, m) DO
    tasks[i - 1] := next[i - 1]
  END ;
  count := m
END ReadClientList ;

PROCEDURE ReadDesktops ;
VAR
  v: LONGCARD ;
  raw: ARRAY [0..1023] OF CHAR ;
  i, j, k, n: CARDINAL ;
BEGIN
  desktops := 1 ;
  IF Props.GetCardinal (root, Atoms.NetNumberOfDesktops, XA_CARDINAL, v) AND
     (v >= 1)
  THEN
    IF v > MaxDesktops THEN v := MaxDesktops END ;
    desktops := VAL (INTEGER, v)
  END ;
  current := 0 ;
  IF Props.GetCardinal (root, Atoms.NetCurrentDesktop, XA_CARDINAL, v) AND
     (v < VAL (LONGCARD, desktops))
  THEN
    current := VAL (INTEGER, v)
  END ;
  FOR i := 0 TO MaxDesktops - 1 DO
    Str.IntToStr (i + 1, names[i])
  END ;
  (* the names arrive as one nul separated list *)
  n := Props.GetTextList (root, Atoms.NetDesktopNames, raw) ;
  i := 0 ;
  k := 0 ;
  WHILE (i < n) AND (k < MaxDesktops) DO
    j := 0 ;
    WHILE (i < n) AND (raw[i] # 0C) DO
      IF j < HIGH (names[k]) THEN names[k][j] := raw[i] ; INC (j) END ;
      INC (i)
    END ;
    IF j > 0
    THEN
      names[k][j] := 0C ;
      Str.Shorten (names[k], j)
    END ;
    INC (i) ;
    INC (k)
  END
END ReadDesktops ;

PROCEDURE ReadActive ;
VAR
  w: LONGCARD ;
BEGIN
  active := None ;
  IF Props.GetCardinal (root, Atoms.NetActiveWindow, XA_WINDOW, w)
  THEN
    active := w
  END
END ReadActive ;

PROCEDURE Init (panel: Window) ;
BEGIN
  owner := panel ;
  count := 0 ;
  ReadDesktops ;
  ReadActive ;
  ReadClientList
END Init ;

PROCEDURE Changed (VAR e: Event) : BOOLEAN ;
VAR
  i: INTEGER ;
BEGIN
  IF e.type # PropertyNotify
  THEN
    RETURN FALSE
  END ;
  IF e.window = root
  THEN
    IF e.atom = Atoms.NetClientList
    THEN
      ReadClientList
    ELSIF e.atom = Atoms.NetActiveWindow
    THEN
      ReadActive
    ELSIF (e.atom = Atoms.NetCurrentDesktop) OR
          (e.atom = Atoms.NetNumberOfDesktops) OR
          (e.atom = Atoms.NetDesktopNames)
    THEN
      ReadDesktops
    ELSE
      RETURN FALSE
    END ;
    RETURN TRUE
  END ;
  i := Find (e.window) ;
  IF i < 0
  THEN
    RETURN FALSE
  END ;
  IF (e.atom = Atoms.NetWmName) OR (e.atom = XA_WM_NAME)
  THEN
    ReadTitle (tasks[i])
  ELSIF e.atom = Atoms.NetWmState
  THEN
    ReadState (tasks[i])
  ELSIF e.atom = Atoms.NetWmDesktop
  THEN
    ReadDesktop (tasks[i])
  ELSE
    RETURN FALSE
  END ;
  RETURN TRUE
END Changed ;

PROCEDURE OnDesktop (VAR t: Task; desk: INTEGER) : BOOLEAN ;
BEGIN
  RETURN (t.desktop = desk) OR (t.desktop = AllDesktops)
END OnDesktop ;

PROCEDURE Occupied (desk: INTEGER) : BOOLEAN ;
VAR
  i: INTEGER ;
BEGIN
  FOR i := 0 TO count - 1 DO
    IF tasks[i].desktop = desk
    THEN
      RETURN TRUE
    END
  END ;
  RETURN FALSE
END Occupied ;

PROCEDURE Send (w: Window; type: Atom; d0, d1, d2: LONGINT) ;
BEGIN
  mx_send_client_message (dpy, root, w, type, RootMask, d0, d1, d2, 0, 0)
END Send ;

PROCEDURE Activate (w: Window) ;
BEGIN
  Send (w, Atoms.NetActiveWindow, SourcePager, 0, 0)
END Activate ;

PROCEDURE Minimize (w: Window) ;
BEGIN
  Send (w, Atoms.WmChangeState, IconicState, 0, 0)
END Minimize ;

PROCEDURE ToggleMaximize (w: Window) ;
BEGIN
  Send (w, Atoms.NetWmState, Toggle, Atoms.NetWmStateMaximizedVert,
        Atoms.NetWmStateMaximizedHorz)
END ToggleMaximize ;

PROCEDURE Close (w: Window) ;
BEGIN
  Send (w, Atoms.NetCloseWindow, 0, SourcePager, 0)
END Close ;

PROCEDURE SendTo (w: Window; desk: INTEGER) ;
BEGIN
  Send (w, Atoms.NetWmDesktop, desk, SourcePager, 0)
END SendTo ;

PROCEDURE SwitchTo (desk: INTEGER) ;
BEGIN
  Send (root, Atoms.NetCurrentDesktop, desk, 0, 0)
END SwitchTo ;

PROCEDURE Logout ;
BEGIN
  Send (root, Atoms.MosaicCommand, Atoms.CommandLogout, 0, 0)
END Logout ;

BEGIN
  owner := None ;
  count := 0 ;
  active := None ;
  current := 0 ;
  desktops := 1
END Tasks.
