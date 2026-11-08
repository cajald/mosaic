MODULE launcher ;

(* mosaic-launcher: browse, search and start installed applications *)

FROM Xlib IMPORT Window, KeySym, XMapWindow, XA_WINDOW,
                 Expose, ConfigureNotify, KeyPress, ButtonPress,
                 ButtonRelease, MotionNotify, ClientMessage ;
FROM XGlue IMPORT Event, mx_send_client_message ;
FROM XServer IMPORT dpy, root ;
FROM Posix IMPORT mx_watch_signals, mx_take_signal, mx_init_locale ;
FROM libc IMPORT exit ;
FROM Gfx IMPORT Surface ;
FROM Widgets IMPORT ListView, TextField, Edit ;
FROM Spawn IMPORT Args ;
FROM Entries IMPORT Entry ;
IMPORT XServer, Atoms, Config, Gfx, Win, Widgets, Dialog, Spawn, Props, Str,
       Entries, Log ;

CONST
  Margin = 10 ;
  CategoryWidth = 150 ;
  DoubleClick = 400 ;
  WheelRows = 3 ;
  SubstructureMasks = 1048576 + 524288 ;

TYPE
  Focus = (OnApps, OnCategories) ;

VAR
  win: Win.Handle ;
  search: TextField ;
  apps, cats: ListView ;
  shown: ARRAY [0..Entries.MaxEntries - 1] OF CARDINAL ;
  focus: Focus ;
  dragging: BOOLEAN ;
  dragList: Focus ;
  lastClick: LONGCARD ;
  lastRow: INTEGER ;
  running: BOOLEAN ;
  event: Event ;

PROCEDURE Matches (e: Entry) : BOOLEAN ;
BEGIN
  IF search.text[0] # 0C
  THEN
    RETURN Str.ContainsNoCase (e^.name, search.text) OR
           Str.ContainsNoCase (e^.comment, search.text)
  END ;
  RETURN (cats.selected <= Entries.AllCategory) OR
         (e^.category = VAL (CARDINAL, cats.selected))
END Matches ;

PROCEDURE Filter ;
VAR
  i: CARDINAL ;
  n: INTEGER ;
BEGIN
  n := 0 ;
  FOR i := 1 TO Entries.count DO
    IF Matches (Entries.entries[i - 1])
    THEN
      shown[n] := i - 1 ;
      INC (n)
    END
  END ;
  apps.count := n ;
  apps.top := 0 ;
  Widgets.ListSelect (apps, 0)
END Filter ;

PROCEDURE Selected () : Entry ;
BEGIN
  IF (apps.selected < 0) OR (apps.selected >= apps.count)
  THEN
    RETURN NIL
  END ;
  RETURN Entries.entries[shown[apps.selected]]
END Selected ;

PROCEDURE AppRow (s: Surface; i, x, y, w, h: INTEGER; selected: BOOLEAN) ;
VAR
  e: Entry ;
  ink: Gfx.Color ;
BEGIN
  e := Entries.entries[shown[i]] ;
  ink := Gfx.Ink ;
  IF selected
  THEN
    Gfx.Fill (s, x, y, w, h, Gfx.Select) ;
    ink := Gfx.SelectInk
  END ;
  Gfx.TextClip (s, x + 6, y + (h - Gfx.lineHeight) DIV 2, w - 12, e^.name,
                ink, FALSE)
END AppRow ;

PROCEDURE CategoryRow (s: Surface; i, x, y, w, h: INTEGER; selected: BOOLEAN) ;
VAR
  ink: Gfx.Color ;
BEGIN
  ink := Gfx.Ink ;
  IF selected
  THEN
    Gfx.Fill (s, x, y, w, h, Gfx.Select) ;
    ink := Gfx.SelectInk
  END ;
  Gfx.TextClip (s, x + 6, y + (h - Gfx.lineHeight) DIV 2, w - 12,
                Entries.categoryNames[i], ink, i = Entries.AllCategory)
END CategoryRow ;

PROCEDURE Layout ;
VAR
  listTop, listBottom: INTEGER ;
BEGIN
  search.x := Margin + Gfx.TextWidth ("Find", TRUE) + 10 ;
  search.y := Margin ;
  search.w := win^.width - search.x - Margin ;
  listTop := Margin + Widgets.FieldHeight + 8 ;
  listBottom := win^.height - Margin - Gfx.lineHeight - 8 ;
  cats.x := Margin ;
  cats.y := listTop ;
  cats.w := CategoryWidth ;
  cats.h := listBottom - listTop ;
  apps.x := Margin + CategoryWidth + 8 ;
  apps.y := listTop ;
  apps.w := win^.width - apps.x - Margin ;
  apps.h := listBottom - listTop ;
  cats.focused := focus = OnCategories ;
  apps.focused := focus = OnApps
END Layout ;

PROCEDURE Draw ;
VAR
  s: Surface ;
  e: Entry ;
  status: ARRAY [0..319] OF CHAR ;
BEGIN
  Layout ;
  s := win^.surface ;
  Widgets.DrawPanel (s, 0, 0, win^.width, win^.height) ;
  Gfx.Text (s, Margin, search.y + (Widgets.FieldHeight - Gfx.lineHeight) DIV 2,
            "Find", Gfx.Ink, TRUE) ;
  Widgets.DrawField (s, search) ;
  Widgets.DrawList (s, cats, CategoryRow) ;
  Widgets.DrawList (s, apps, AppRow) ;
  e := Selected () ;
  IF e # NIL
  THEN
    IF e^.comment[0] # 0C
    THEN
      IF Str.Assign (e^.comment, status) THEN END
    ELSE
      IF Str.Assign (e^.name, status) THEN END
    END
  ELSIF Entries.count = 0
  THEN
    status := "No applications were found."
  ELSE
    status := "Nothing matches."
  END ;
  Gfx.TextClip (s, Margin, win^.height - Margin - Gfx.lineHeight - 2,
                win^.width - 2 * Margin, status, Gfx.InkDim, FALSE) ;
  Gfx.Flush (s)
END Draw ;

PROCEDURE Ignore (VAR e: Event) ;
BEGIN
  IF (e.window = win^.window) AND (e.type = Expose)
  THEN
    Draw
  END
END Ignore ;

PROCEDURE Fail (name, reason: ARRAY OF CHAR) ;
VAR
  text: ARRAY [0..511] OF CHAR ;
BEGIN
  IF Str.Assign (name, text) AND Str.Append (" cannot be started: ", text) AND
     Str.Append (reason, text) AND Str.Append (".", text)
  THEN
  END ;
  Dialog.Message (win^.window, "Applications", text, Ignore)
END Fail ;

PROCEDURE Launch ;
VAR
  e: Entry ;
  a: Args ;
  program, why: ARRAY [0..511] OF CHAR ;
BEGIN
  e := Selected () ;
  IF e = NIL
  THEN
    RETURN
  END ;
  IF NOT Entries.Command (e^, a, why)
  THEN
    Fail (e^.name, why) ;
    RETURN
  END ;
  IF Spawn.Get (a, 0, program) AND NOT Spawn.Executable (program)
  THEN
    IF Str.Assign ("the program '", why) AND Str.Append (program, why) AND
       Str.Append ("' is not installed", why)
    THEN
    END ;
    Fail (e^.name, why) ;
    RETURN
  END ;
  IF Spawn.Run (a, e^.dir) < 0
  THEN
    Fail (e^.name, "the system refused to start it") ;
    RETURN
  END ;
  running := FALSE
END Launch ;

PROCEDURE OnKey (VAR e: Event) ;
VAR
  sym: KeySym ;
  text: ARRAY [0..31] OF CHAR ;
  edit: Edit ;
BEGIN
  Win.Key (win, e, sym, text) ;
  IF sym = Widgets.XKTab
  THEN
    IF focus = OnApps THEN focus := OnCategories ELSE focus := OnApps END
  ELSIF (sym = Widgets.XKUp) OR (sym = Widgets.XKDown) OR
        (sym = Widgets.XKPageUp) OR (sym = Widgets.XKPageDown)
  THEN
    IF focus = OnCategories
    THEN
      IF Widgets.ListKey (cats, sym)
      THEN
        search.text[0] := 0C ;
        search.cursor := 0 ;
        Filter
      END
    ELSIF Widgets.ListKey (apps, sym)
    THEN
    END
  ELSIF Widgets.IsEnter (sym)
  THEN
    Launch
  ELSIF sym = Widgets.XKEscape
  THEN
    running := FALSE
  ELSE
    edit := Widgets.FieldKey (search, sym, text) ;
    IF edit = Widgets.EditChanged
    THEN
      (* searching always covers every category *)
      Widgets.ListSelect (cats, Entries.AllCategory) ;
      focus := OnApps ;
      Filter
    END
  END ;
  IF running
  THEN
    Draw
  END
END OnKey ;

PROCEDURE OnPress (VAR e: Event) ;
VAR
  row: INTEGER ;
BEGIN
  IF (e.detail = 4) OR (e.detail = 5)
  THEN
    row := WheelRows ;
    IF e.detail = 4 THEN row := -row END ;
    IF Widgets.Inside (e.x, e.y, cats.x, cats.y, cats.w, cats.h)
    THEN
      Widgets.ListScroll (cats, row)
    ELSE
      Widgets.ListScroll (apps, row)
    END ;
    Draw ;
    RETURN
  END ;
  IF e.detail # 1
  THEN
    RETURN
  END ;
  IF Widgets.ListOnScrollbar (apps, e.x, e.y)
  THEN
    dragging := TRUE ;
    dragList := OnApps ;
    Widgets.ListDragThumb (apps, e.y)
  ELSIF Widgets.ListOnScrollbar (cats, e.x, e.y)
  THEN
    dragging := TRUE ;
    dragList := OnCategories ;
    Widgets.ListDragThumb (cats, e.y)
  ELSE
    row := Widgets.ListRowAt (cats, e.x, e.y) ;
    IF row >= 0
    THEN
      focus := OnCategories ;
      Widgets.ListSelect (cats, row) ;
      search.text[0] := 0C ;
      search.cursor := 0 ;
      Filter
    ELSE
      row := Widgets.ListRowAt (apps, e.x, e.y) ;
      IF row >= 0
      THEN
        focus := OnApps ;
        Widgets.ListSelect (apps, row) ;
        IF (row = lastRow) AND (e.time - lastClick < DoubleClick)
        THEN
          lastRow := -1 ;
          Launch
        ELSE
          lastRow := row ;
          lastClick := e.time
        END
      END
    END
  END ;
  IF running
  THEN
    Draw
  END
END OnPress ;

PROCEDURE Dispatch (VAR e: Event) ;
BEGIN
  IF Win.IsClose (win, e)
  THEN
    running := FALSE ;
    RETURN
  END ;
  IF e.window # win^.window
  THEN
    RETURN
  END ;
  CASE e.type OF
    Expose:
      IF e.detail = 0 THEN Draw END |
    ConfigureNotify:
      IF Win.Configured (win, e) THEN Draw END |
    KeyPress:
      OnKey (e) |
    ButtonPress:
      OnPress (e) |
    ButtonRelease:
      dragging := FALSE |
    MotionNotify:
      IF dragging
      THEN
        IF dragList = OnApps
        THEN
          Widgets.ListDragThumb (apps, e.y)
        ELSE
          Widgets.ListDragThumb (cats, e.y)
        END ;
        Draw
      END
  ELSE
  END
END Dispatch ;

(* a second launcher just raises the first one *)
PROCEDURE RaiseExisting () : BOOLEAN ;
VAR
  list: ARRAY [0..1023] OF LONGCARD ;
  n, i: CARDINAL ;
  class: ARRAY [0..63] OF CHAR ;
BEGIN
  n := Props.GetCardinals (root, Atoms.NetClientList, XA_WINDOW, list) ;
  FOR i := 1 TO n DO
    IF Props.GetText (list[i - 1], Atoms.WmClass, class) AND
       Str.Equal (class, "mosaic-launcher")
    THEN
      mx_send_client_message (dpy, root, list[i - 1], Atoms.NetActiveWindow,
                              SubstructureMasks, 2, 0, 0, 0, 0) ;
      RETURN TRUE
    END
  END ;
  RETURN FALSE
END RaiseExisting ;

BEGIN
  Log.SetProgram ("mosaic-launcher") ;
  mx_init_locale ;
  mx_watch_signals ;
  IF NOT XServer.Open ()
  THEN
    exit (1)
  END ;
  Config.Load ;
  Atoms.Init ;
  IF RaiseExisting ()
  THEN
    XServer.Close ;
    exit (0)
  END ;
  IF NOT Gfx.Init ()
  THEN
    XServer.Close ;
    exit (1)
  END ;
  Entries.Load ;
  win := Win.Create ("Applications", "mosaic-launcher", 620, 440, 420, 260) ;
  search.focused := TRUE ;
  Widgets.SetField (search, "") ;
  cats.rowHeight := Gfx.lineHeight + 6 ;
  cats.count := Entries.Categories ;
  cats.top := 0 ;
  apps.rowHeight := Gfx.lineHeight + 6 ;
  focus := OnApps ;
  Layout ;
  Widgets.ListSelect (cats, Entries.AllCategory) ;
  Filter ;
  dragging := FALSE ;
  lastRow := -1 ;
  lastClick := 0 ;
  IF XMapWindow (dpy, win^.window) = 0 THEN END ;
  running := TRUE ;
  WHILE running DO
    IF XServer.WaitEvent (1000) AND XServer.NextEvent (event)
    THEN
      Dispatch (event)
    END ;
    IF mx_take_signal () # 0
    THEN
      running := FALSE
    END
  END ;
  Win.Destroy (win) ;
  Gfx.Done ;
  XServer.Close ;
  exit (0)
END launcher.
