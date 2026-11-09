MODULE files ;

(* mosaic-files: browse folders and copy, move, rename and delete *)

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM Xlib IMPORT KeySym, XMapWindow, ControlMask, Mod1Mask,
                 Expose, ConfigureNotify, KeyPress, ButtonPress,
                 ButtonRelease, MotionNotify ;
FROM XGlue IMPORT Event ;
FROM XServer IMPORT dpy ;
FROM Posix IMPORT ENOENT, EEXIST, ENAMETOOLONG, strerror, mx_watch_signals, mx_take_signal,
                  mx_init_locale, mx_format_time ;
FROM libc IMPORT exit, getenv, getcwd ;
FROM Args IMPORT GetArg, Narg ;
FROM Gfx IMPORT Surface ;
FROM Widgets IMPORT ListView, TextField, Button, Edit ;
FROM Spawn IMPORT Args ;
FROM Fs IMPORT Path, Item, Listing ;
IMPORT XServer, Atoms, Config, Gfx, Win, Widgets, Menu, Dialog, Spawn, Str,
       Fs, Log ;

CONST
  Margin = 8 ;
  Buttons = 7 ;
  SizeWidth = 80 ;
  DateWidth = 130 ;
  DoubleClick = 400 ;
  WheelRows = 3 ;
  XKH = 068H ;
  XKL = 06CH ;
  XKC = 063H ;
  XKX = 078H ;
  XKV = 076H ;
  XKN = 06EH ;
  XKQ = 071H ;
  XKW = 077H ;

TYPE
  Action = (GoUp, NewFolder, CopyItem, CutItem, PasteItem, RenameItem,
            DeleteItem, OpenItem, Reload, ToggleHidden) ;

VAR
  win: Win.Handle ;
  cwd: Path ;
  listing: Listing ;
  list: ListView ;
  location: TextField ;
  editingLocation: BOOLEAN ;
  toolbar: ARRAY [0..Buttons - 1] OF Button ;
  toolbarAction: ARRAY [0..Buttons - 1] OF Action ;
  pressedButton: INTEGER ;
  showHidden: BOOLEAN ;
  clipboard: Path ;
  clipboardCut: BOOLEAN ;
  status: ARRAY [0..511] OF CHAR ;
  dragging: BOOLEAN ;
  lastClick: LONGCARD ;
  lastRow: INTEGER ;
  running: BOOLEAN ;
  headerY: INTEGER ;
  event: Event ;

PROCEDURE ErrorText (err: INTEGER; VAR text: ARRAY OF CHAR) ;
BEGIN
  IF err = Fs.ETooDeep
  THEN
    IF Str.Assign ("folders are nested too deeply", text) THEN END
  ELSIF err = Fs.EIntoItself
  THEN
    IF Str.Assign ("a folder cannot go inside itself", text) THEN END
  ELSIF NOT Str.FromC (strerror (err), text)
  THEN
    text[0] := 0C
  END
END ErrorText ;

(* "Cannot <what> 'name': reason" in a dialog *)
PROCEDURE Report (what: ARRAY OF CHAR; err: INTEGER) ;
VAR
  text: ARRAY [0..1023] OF CHAR ;
  reason: ARRAY [0..255] OF CHAR ;
  shown: ARRAY [0..Fs.PathMax - 1] OF CHAR ;
BEGIN
  ErrorText (err, reason) ;
  Str.Printable (Fs.failedPath, shown) ;
  IF Str.Assign ("Cannot ", text) AND Str.Append (what, text) AND
     Str.Append (" '", text)
  THEN
  END ;
  Str.Shorten (shown, 600) ;
  IF Str.Append (shown, text) AND Str.Append ("': ", text) AND
     Str.Append (reason, text) AND Str.Append (".", text)
  THEN
  END ;
  Dialog.Message (win^.window, "Files", text, Repaint)
END Report ;

PROCEDURE Selected () : Item ;
BEGIN
  IF (list.selected < 0) OR (list.selected >= list.count)
  THEN
    RETURN NIL
  END ;
  RETURN listing.items^[list.selected]
END Selected ;

PROCEDURE SelectedPath (VAR path: ARRAY OF CHAR) : BOOLEAN ;
VAR
  it: Item ;
BEGIN
  it := Selected () ;
  RETURN (it # NIL) AND Fs.Join (cwd, it^.name, path)
END SelectedPath ;

PROCEDURE SelectName (name: ARRAY OF CHAR) ;
VAR
  i: CARDINAL ;
BEGIN
  FOR i := 1 TO listing.count DO
    IF Str.Equal (listing.items^[i - 1]^.name, name)
    THEN
      Widgets.ListSelect (list, i - 1) ;
      RETURN
    END
  END
END SelectName ;

PROCEDURE UpdateTitle ;
VAR
  title: ARRAY [0..Fs.PathMax + 15] OF CHAR ;
  shown: ARRAY [0..Fs.PathMax - 1] OF CHAR ;
BEGIN
  Str.Printable (cwd, shown) ;
  IF Str.Assign ("Files: ", title) AND Str.Append (shown, title) THEN END ;
  Win.SetTitle (win, title)
END UpdateTitle ;

(* list dir; on failure stay where we are and say why *)
PROCEDURE Enter (dir: ARRAY OF CHAR; select: ARRAY OF CHAR) : BOOLEAN ;
VAR
  fresh: Listing ;
  err: INTEGER ;
BEGIN
  Fs.Init (fresh) ;
  err := Fs.Read (dir, showHidden, fresh) ;
  IF err # 0
  THEN
    Fs.Free (fresh) ;
    Report ("open folder", err) ;
    RETURN FALSE
  END ;
  Fs.Free (listing) ;
  listing := fresh ;
  IF NOT Str.Assign (dir, cwd)
  THEN
    cwd := "/"
  END ;
  list.count := listing.count ;
  list.top := 0 ;
  list.selected := -1 ;
  Widgets.ListSelect (list, 0) ;
  IF select[0] # 0C
  THEN
    SelectName (select)
  END ;
  Widgets.SetField (location, cwd) ;
  UpdateTitle ;
  status[0] := 0C ;
  RETURN TRUE
END Enter ;

PROCEDURE Refresh (select: ARRAY OF CHAR) ;
VAR
  here: Path ;
BEGIN
  here := cwd ;
  (* the folder may be gone; climb until something can be listed *)
  WHILE NOT Enter (here, select) AND NOT Str.Equal (here, "/") DO
    Fs.Parent (here)
  END
END Refresh ;

PROCEDURE HumanSize (n: LONGINT; VAR text: ARRAY OF CHAR) ;
VAR
  units: ARRAY [0..4] OF CHAR ;
  u: CARDINAL ;
  whole, tenth: LONGINT ;
  part: ARRAY [0..23] OF CHAR ;
BEGIN
  units := "BKMGT" ;
  IF n < 1024
  THEN
    Str.IntToStr (n, text) ;
    IF Str.Append (" B", text) THEN END ;
    RETURN
  END ;
  u := 0 ;
  whole := n ;
  tenth := 0 ;
  WHILE (whole >= 1024) AND (u < 4) DO
    tenth := (whole MOD 1024) * 10 DIV 1024 ;
    whole := whole DIV 1024 ;
    INC (u)
  END ;
  Str.IntToStr (whole, text) ;
  IF whole < 10
  THEN
    Str.IntToStr (tenth, part) ;
    IF Str.Append (".", text) AND Str.Append (part, text) THEN END
  END ;
  IF Str.AppendChar (' ', text) AND Str.AppendChar (units[u], text) THEN END
END HumanSize ;

PROCEDURE DrawGlyph (s: Surface; it: Item; x, y: INTEGER; ink: Gfx.Color) ;
BEGIN
  IF it^.isDir
  THEN
    Gfx.Fill (s, x, y + 1, 5, 2, ink) ;
    Gfx.Fill (s, x, y + 3, 11, 8, ink)
  ELSE
    Gfx.Outline (s, x + 1, y, 9, 11, ink) ;
    Gfx.Line (s, x + 3, y + 3, x + 7, y + 3, ink) ;
    Gfx.Line (s, x + 3, y + 5, x + 7, y + 5, ink)
  END
END DrawGlyph ;

PROCEDURE Row (s: Surface; i, x, y, w, h: INTEGER; selected: BOOLEAN) ;
VAR
  it: Item ;
  ink: Gfx.Color ;
  name: ARRAY [0..Fs.NameMax + 7] OF CHAR ;
  text: ARRAY [0..63] OF CHAR ;
  ty, nameWidth, tw: INTEGER ;
BEGIN
  it := listing.items^[i] ;
  ink := Gfx.Ink ;
  IF selected
  THEN
    Gfx.Fill (s, x, y, w, h, Gfx.Select) ;
    ink := Gfx.SelectInk
  ELSIF it^.broken
  THEN
    ink := Gfx.InkDim
  END ;
  ty := y + (h - Gfx.lineHeight) DIV 2 ;
  DrawGlyph (s, it, x + 5, y + (h - 11) DIV 2, ink) ;
  Str.Printable (it^.name, name) ;
  IF it^.isLink
  THEN
    IF Str.Append (" →", name) THEN END
  ELSIF it^.isDir
  THEN
    IF Str.Append ("/", name) THEN END
  END ;
  nameWidth := w - SizeWidth - DateWidth - 28 ;
  Gfx.TextClip (s, x + 22, ty, nameWidth, name, ink, it^.isDir) ;
  IF NOT it^.isDir
  THEN
    HumanSize (it^.size, text) ;
    tw := Gfx.TextWidth (text, FALSE) ;
    Gfx.Text (s, x + w - DateWidth - 8 - tw, ty, text, ink, FALSE)
  END ;
  IF mx_format_time (it^.mtime, "%Y-%m-%d %H:%M", text, HIGH (text)) > 0
  THEN
    Gfx.Text (s, x + w - DateWidth + 4, ty, text, ink, FALSE)
  END
END Row ;

PROCEDURE Layout ;
VAR
  i, x: INTEGER ;
BEGIN
  x := Margin ;
  FOR i := 0 TO Buttons - 1 DO
    toolbar[i].x := x ;
    toolbar[i].y := Margin ;
    toolbar[i].w := Gfx.TextWidth (toolbar[i].label, FALSE) + 20 ;
    toolbar[i].down := i = pressedButton ;
    INC (x, toolbar[i].w + 4)
  END ;
  location.x := Margin + Gfx.TextWidth ("Location", TRUE) + 10 ;
  location.y := Margin + Widgets.ButtonHeight + 8 ;
  location.w := win^.width - location.x - Margin ;
  location.focused := editingLocation ;
  headerY := location.y + Widgets.FieldHeight + 8 ;
  list.x := Margin ;
  list.y := headerY + Gfx.lineHeight + 6 ;
  list.w := win^.width - 2 * Margin ;
  list.h := win^.height - list.y - Gfx.lineHeight - 12 ;
  list.focused := NOT editingLocation
END Layout ;

PROCEDURE StatusLine (VAR text: ARRAY OF CHAR) ;
VAR
  n: ARRAY [0..23] OF CHAR ;
  it: Item ;
  shown: ARRAY [0..Fs.NameMax + 7] OF CHAR ;
BEGIN
  IF status[0] # 0C
  THEN
    IF Str.Assign (status, text) THEN END ;
    RETURN
  END ;
  Str.IntToStr (listing.count, n) ;
  IF Str.Assign (n, text) THEN END ;
  IF listing.count = 1
  THEN
    IF Str.Append (" item", text) THEN END
  ELSE
    IF Str.Append (" items", text) THEN END
  END ;
  IF listing.skipped > 0
  THEN
    Str.IntToStr (listing.skipped, n) ;
    IF Str.Append (", ", text) AND Str.Append (n, text) AND
       Str.Append (" unreadable", text)
    THEN
    END
  END ;
  it := Selected () ;
  IF it # NIL
  THEN
    Str.Printable (it^.name, shown) ;
    IF Str.Append ("   ·   ", text) AND Str.Append (shown, text) THEN END ;
    IF it^.broken AND Str.Append (" (broken link)", text) THEN END
  END ;
  IF clipboard[0] # 0C
  THEN
    IF clipboardCut
    THEN
      IF Str.Append ("   ·   1 item cut", text) THEN END
    ELSE
      IF Str.Append ("   ·   1 item copied", text) THEN END
    END
  END
END StatusLine ;

PROCEDURE Draw ;
VAR
  s: Surface ;
  i: INTEGER ;
  text: ARRAY [0..1023] OF CHAR ;
BEGIN
  Layout ;
  s := win^.surface ;
  Widgets.DrawPanel (s, 0, 0, win^.width, win^.height) ;
  FOR i := 0 TO Buttons - 1 DO
    Widgets.DrawButton (s, toolbar[i])
  END ;
  Gfx.Text (s, Margin, location.y + (Widgets.FieldHeight - Gfx.lineHeight) DIV 2,
            "Location", Gfx.Ink, TRUE) ;
  Widgets.DrawField (s, location) ;
  Gfx.Text (s, list.x + 24, headerY, "Name", Gfx.InkDim, TRUE) ;
  Gfx.Text (s, list.x + list.w - Widgets.ScrollbarWidth - DateWidth - 8 -
            Gfx.TextWidth ("Size", TRUE), headerY, "Size", Gfx.InkDim, TRUE) ;
  Gfx.Text (s, list.x + list.w - Widgets.ScrollbarWidth - DateWidth + 4 - 2,
            headerY, "Modified", Gfx.InkDim, TRUE) ;
  Widgets.DrawList (s, list, Row) ;
  StatusLine (text) ;
  Gfx.TextClip (s, Margin, win^.height - Gfx.lineHeight - 6,
                win^.width - 2 * Margin, text, Gfx.InkDim, FALSE) ;
  Gfx.Flush (s)
END Draw ;

PROCEDURE Repaint (VAR e: Event) ;
BEGIN
  IF e.window = win^.window
  THEN
    IF e.type = Expose
    THEN
      Draw
    ELSIF (e.type = ConfigureNotify) AND Win.Configured (win, e)
    THEN
      Draw
    END
  END
END Repaint ;

PROCEDURE OpenSelected ;
VAR
  it: Item ;
  path: Path ;
  a: Args ;
BEGIN
  it := Selected () ;
  IF (it = NIL) OR NOT SelectedPath (path)
  THEN
    RETURN
  END ;
  IF it^.isDir
  THEN
    IF Enter (path, "") THEN END
  ELSIF it^.broken
  THEN
    IF Str.Assign (path, Fs.failedPath) THEN END ;
    Report ("open", ENOENT)
  ELSIF NOT Spawn.Executable ("xdg-open")
  THEN
    Dialog.Message (win^.window, "Files",
                    "Files cannot be opened because xdg-open is not installed.",
                    Repaint)
  ELSE
    Spawn.Clear (a) ;
    IF Spawn.Add (a, "xdg-open") AND Spawn.Add (a, path) AND
       (Spawn.Run (a, cwd) > 0)
    THEN
      status := "Opening with the preferred application…"
    END
  END
END OpenSelected ;

PROCEDURE GoParent ;
VAR
  up: Path ;
  name: ARRAY [0..Fs.NameMax - 1] OF CHAR ;
BEGIN
  IF Str.Equal (cwd, "/")
  THEN
    RETURN
  END ;
  up := cwd ;
  Fs.Parent (up) ;
  Fs.BaseName (cwd, name) ;
  IF Enter (up, name) THEN END
END GoParent ;

PROCEDURE AskName (title, text: ARRAY OF CHAR; VAR name: ARRAY OF CHAR) : BOOLEAN ;
VAR
  value: ARRAY [0..4095] OF CHAR ;
BEGIN
  IF NOT Str.Assign (name, value) THEN value[0] := 0C END ;
  LOOP
    IF NOT Dialog.Prompt (win^.window, title, text, value, Repaint)
    THEN
      RETURN FALSE
    END ;
    IF Fs.ValidName (value) AND Str.Assign (value, name)
    THEN
      RETURN TRUE
    END ;
    Dialog.Message (win^.window, title,
                    "A name cannot be empty, '.', '..', contain '/' or be longer than 255 bytes.",
                    Repaint)
  END
END AskName ;

PROCEDURE MakeFolder ;
VAR
  name: ARRAY [0..Fs.NameMax - 1] OF CHAR ;
  path: Path ;
  err: INTEGER ;
BEGIN
  name := "New Folder" ;
  IF NOT AskName ("New Folder", "Name of the new folder:", name)
  THEN
    RETURN
  END ;
  IF NOT Fs.Join (cwd, name, path)
  THEN
    IF Str.Assign (cwd, Fs.failedPath) THEN END ;
    Report ("create a folder in", ENAMETOOLONG) ;
    RETURN
  END ;
  err := Fs.MakeDir (path) ;
  IF err # 0
  THEN
    Report ("create folder", err)
  END ;
  Refresh (name)
END MakeFolder ;

PROCEDURE RenameSelected ;
VAR
  it: Item ;
  name: ARRAY [0..Fs.NameMax - 1] OF CHAR ;
  source, target: Path ;
  err: INTEGER ;
BEGIN
  it := Selected () ;
  IF (it = NIL) OR NOT SelectedPath (source)
  THEN
    RETURN
  END ;
  IF Str.Assign (it^.name, name) THEN END ;
  IF NOT AskName ("Rename", "New name:", name) OR Str.Equal (name, it^.name)
  THEN
    RETURN
  END ;
  IF NOT Fs.Join (cwd, name, target)
  THEN
    IF Str.Assign (cwd, Fs.failedPath) THEN END ;
    Report ("rename in", ENAMETOOLONG) ;
    RETURN
  END ;
  err := Fs.Rename (source, target) ;
  IF err = EEXIST
  THEN
    IF Str.Assign (target, Fs.failedPath) THEN END ;
    Report ("rename to", err)
  ELSIF err # 0
  THEN
    Report ("rename", err)
  END ;
  Refresh (name)
END RenameSelected ;

PROCEDURE DeleteSelected ;
VAR
  it: Item ;
  path: Path ;
  question: ARRAY [0..511] OF CHAR ;
  shown: ARRAY [0..Fs.NameMax + 7] OF CHAR ;
  err: INTEGER ;
  next: ARRAY [0..Fs.NameMax - 1] OF CHAR ;
BEGIN
  it := Selected () ;
  IF (it = NIL) OR NOT SelectedPath (path)
  THEN
    RETURN
  END ;
  Str.Printable (it^.name, shown) ;
  IF Str.Assign ("Delete '", question) AND Str.Append (shown, question) THEN END ;
  IF it^.isDir AND NOT it^.isLink
  THEN
    IF Str.Append ("' and everything inside it? This cannot be undone.",
                   question) THEN END
  ELSE
    IF Str.Append ("'? This cannot be undone.", question) THEN END
  END ;
  IF NOT Dialog.Confirm (win^.window, "Delete", question, "Delete", Repaint)
  THEN
    RETURN
  END ;
  (* keep the cursor near the deleted row *)
  next[0] := 0C ;
  IF list.selected + 1 < list.count
  THEN
    IF Str.Assign (listing.items^[list.selected + 1]^.name, next) THEN END
  ELSIF list.selected > 0
  THEN
    IF Str.Assign (listing.items^[list.selected - 1]^.name, next) THEN END
  END ;
  err := Fs.Delete (path) ;
  IF err # 0
  THEN
    Report ("delete", err) ;
    Refresh (it^.name)
  ELSE
    IF Str.Equal (clipboard, path) THEN clipboard[0] := 0C END ;
    Refresh (next)
  END
END DeleteSelected ;

PROCEDURE Remember (cut: BOOLEAN) ;
BEGIN
  IF SelectedPath (clipboard)
  THEN
    clipboardCut := cut
  ELSE
    clipboard[0] := 0C
  END
END Remember ;

PROCEDURE Paste ;
VAR
  created: Path ;
  name: ARRAY [0..Fs.NameMax - 1] OF CHAR ;
  err: INTEGER ;
BEGIN
  IF clipboard[0] = 0C
  THEN
    RETURN
  END ;
  IF clipboardCut
  THEN
    err := Fs.Move (clipboard, cwd, created)
  ELSE
    err := Fs.Copy (clipboard, cwd, created)
  END ;
  IF err # 0
  THEN
    IF clipboardCut THEN Report ("move", err) ELSE Report ("copy", err) END ;
    Refresh ("") ;
    RETURN
  END ;
  IF clipboardCut
  THEN
    clipboard[0] := 0C
  END ;
  Fs.BaseName (created, name) ;
  Refresh (name)
END Paste ;

PROCEDURE Run (a: Action) ;
VAR
  it: Item ;
BEGIN
  it := Selected () ;
  CASE a OF
    GoUp: GoParent |
    NewFolder: MakeFolder |
    CopyItem: Remember (FALSE) |
    CutItem: Remember (TRUE) |
    PasteItem: Paste |
    RenameItem: RenameSelected |
    DeleteItem: DeleteSelected |
    OpenItem: OpenSelected |
    Reload:
      IF it # NIL THEN Refresh (it^.name) ELSE Refresh ("") END |
    ToggleHidden:
      showHidden := NOT showHidden ;
      IF it # NIL THEN Refresh (it^.name) ELSE Refresh ("") END
  END ;
  IF running
  THEN
    Draw
  END
END Run ;

PROCEDURE ContextMenu (VAR e: Event) ;
VAR
  m: Menu.Menu ;
  row: INTEGER ;
  onItem: BOOLEAN ;
BEGIN
  row := Widgets.ListRowAt (list, e.x, e.y) ;
  IF row >= 0
  THEN
    Widgets.ListSelect (list, row)
  END ;
  onItem := row >= 0 ;
  Draw ;
  Menu.Clear (m) ;
  Menu.Add (m, "Open", onItem) ;
  Menu.AddSeparator (m) ;
  Menu.Add (m, "Copy", onItem) ;
  Menu.Add (m, "Cut", onItem) ;
  Menu.Add (m, "Paste", clipboard[0] # 0C) ;
  Menu.AddSeparator (m) ;
  Menu.Add (m, "Rename…", onItem) ;
  Menu.Add (m, "Delete…", onItem) ;
  Menu.AddSeparator (m) ;
  Menu.Add (m, "New Folder…", TRUE) ;
  Menu.AddChecked (m, "Show Hidden Files", showHidden) ;
  Menu.Add (m, "Refresh", TRUE) ;
  CASE Menu.Popup (m, e.xRoot, e.yRoot, e.time, Repaint) OF
    0: Run (OpenItem) |
    2: Run (CopyItem) |
    3: Run (CutItem) |
    4: Run (PasteItem) |
    6: Run (RenameItem) |
    7: Run (DeleteItem) |
    9: Run (NewFolder) |
    10: Run (ToggleHidden) |
    11: Run (Reload)
  ELSE
    Draw
  END
END ContextMenu ;

(* jump to the next name starting with the typed character *)
PROCEDURE TypeAhead (c: CHAR) ;
VAR
  i, start: INTEGER ;
BEGIN
  IF list.count = 0
  THEN
    RETURN
  END ;
  start := list.selected ;
  FOR i := 1 TO list.count DO
    IF Str.Lower (listing.items^[(start + i) MOD list.count]^.name[0]) =
       Str.Lower (c)
    THEN
      Widgets.ListSelect (list, (start + i) MOD list.count) ;
      RETURN
    END
  END
END TypeAhead ;

PROCEDURE LocationKey (sym: KeySym; VAR text: ARRAY OF CHAR) ;
VAR
  target: Path ;
BEGIN
  CASE Widgets.FieldKey (location, sym, text) OF
    Widgets.EditEnter:
      IF (location.text[0] # '/') OR NOT Str.Assign (location.text, target)
      THEN
        Dialog.Message (win^.window, "Location",
                        "Type an absolute path that starts with '/'.", Repaint)
      ELSIF Enter (target, "")
      THEN
        editingLocation := FALSE
      END |
    Widgets.EditCancel:
      Widgets.SetField (location, cwd) ;
      editingLocation := FALSE
  ELSE
  END
END LocationKey ;

PROCEDURE OnKey (VAR e: Event) ;
VAR
  sym: KeySym ;
  text: ARRAY [0..31] OF CHAR ;
  ctrl: BOOLEAN ;
BEGIN
  Win.Key (win, e, sym, text) ;
  ctrl := ODD (e.state DIV ControlMask) ;
  status[0] := 0C ;
  IF ctrl AND ((sym = XKQ) OR (sym = XKW))
  THEN
    running := FALSE ;
    RETURN
  ELSIF ctrl AND (sym = XKL)
  THEN
    editingLocation := TRUE
  ELSIF editingLocation
  THEN
    LocationKey (sym, text)
  ELSIF ctrl AND (sym = XKC) THEN Run (CopyItem)
  ELSIF ctrl AND (sym = XKX) THEN Run (CutItem)
  ELSIF ctrl AND (sym = XKV) THEN Run (PasteItem)
  ELSIF ctrl AND (sym = XKH) THEN Run (ToggleHidden)
  ELSIF ctrl AND (sym = XKN) THEN Run (NewFolder)
  ELSIF Widgets.IsEnter (sym) THEN Run (OpenItem)
  ELSIF (sym = Widgets.XKBackSpace) OR
        (sym = Widgets.XKUp) AND ODD (e.state DIV Mod1Mask)
  THEN
    Run (GoUp)
  ELSIF sym = Widgets.XKDelete THEN Run (DeleteItem)
  ELSIF sym = Widgets.XKF2 THEN Run (RenameItem)
  ELSIF sym = Widgets.XKF5 THEN Run (Reload)
  ELSIF Widgets.ListKey (list, sym)
  THEN
  ELSIF (NOT ctrl) AND (text[0] > ' ') AND (text[1] = 0C)
  THEN
    TypeAhead (text[0])
  END ;
  IF running
  THEN
    Draw
  END
END OnKey ;

PROCEDURE OnPress (VAR e: Event) ;
VAR
  i, row: INTEGER ;
BEGIN
  status[0] := 0C ;
  IF (e.detail = 4) OR (e.detail = 5)
  THEN
    IF e.detail = 4 THEN row := -WheelRows ELSE row := WheelRows END ;
    Widgets.ListScroll (list, row) ;
    Draw ;
    RETURN
  END ;
  IF e.detail = 3
  THEN
    ContextMenu (e) ;
    RETURN
  END ;
  IF e.detail # 1
  THEN
    RETURN
  END ;
  FOR i := 0 TO Buttons - 1 DO
    IF Widgets.OnButton (toolbar[i], e.x, e.y)
    THEN
      pressedButton := i ;
      Draw ;
      RETURN
    END
  END ;
  IF Widgets.Inside (e.x, e.y, location.x, location.y, location.w,
                     Widgets.FieldHeight)
  THEN
    editingLocation := TRUE
  ELSIF Widgets.ListOnScrollbar (list, e.x, e.y)
  THEN
    editingLocation := FALSE ;
    dragging := TRUE ;
    Widgets.ListDragThumb (list, e.y)
  ELSE
    editingLocation := FALSE ;
    row := Widgets.ListRowAt (list, e.x, e.y) ;
    IF row >= 0
    THEN
      Widgets.ListSelect (list, row) ;
      IF (row = lastRow) AND (e.time - lastClick < DoubleClick)
      THEN
        lastRow := -1 ;
        Run (OpenItem) ;
        RETURN
      END ;
      lastRow := row ;
      lastClick := e.time
    END
  END ;
  Draw
END OnPress ;

PROCEDURE OnRelease (VAR e: Event) ;
VAR
  i: INTEGER ;
BEGIN
  dragging := FALSE ;
  IF pressedButton >= 0
  THEN
    i := pressedButton ;
    pressedButton := -1 ;
    IF Widgets.OnButton (toolbar[i], e.x, e.y)
    THEN
      Run (toolbarAction[i])
    ELSE
      Draw
    END
  END
END OnRelease ;

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
    KeyPress: OnKey (e) |
    ButtonPress: OnPress (e) |
    ButtonRelease: OnRelease (e) |
    MotionNotify:
      IF dragging
      THEN
        Widgets.ListDragThumb (list, e.y) ;
        Draw
      END
  ELSE
  END
END Dispatch ;

PROCEDURE AddTool (i: INTEGER; label: ARRAY OF CHAR; a: Action) ;
BEGIN
  Widgets.SetButton (toolbar[i], label, 0, 0, 0) ;
  toolbarAction[i] := a
END AddTool ;

(* the folder to open first: argument, current directory or home *)
PROCEDURE StartFolder (VAR dir: ARRAY OF CHAR) ;
VAR
  p: ADDRESS ;
  arg: Path ;
BEGIN
  IF (Narg () > 1) AND GetArg (arg, 1) AND (arg[0] = '/') AND
     Str.Assign (arg, dir)
  THEN
    RETURN
  END ;
  IF (Narg () > 1) AND GetArg (arg, 1) AND
     (getcwd (ADR (dir), HIGH (dir)) # NIL) AND Fs.Join (dir, arg, dir)
  THEN
    RETURN
  END ;
  p := getenv (ADR ("HOME")) ;
  IF (p = NIL) OR NOT Str.FromC (p, dir)
  THEN
    IF Str.Assign ("/", dir) THEN END
  END
END StartFolder ;

BEGIN
  Log.SetProgram ("mosaic-files") ;
  mx_init_locale ;
  mx_watch_signals ;
  IF NOT XServer.Open ()
  THEN
    exit (1)
  END ;
  Config.Load ;
  Atoms.Init ;
  IF NOT Gfx.Init ()
  THEN
    XServer.Close ;
    exit (1)
  END ;
  Fs.Init (listing) ;
  AddTool (0, "Up", GoUp) ;
  AddTool (1, "New Folder", NewFolder) ;
  AddTool (2, "Copy", CopyItem) ;
  AddTool (3, "Cut", CutItem) ;
  AddTool (4, "Paste", PasteItem) ;
  AddTool (5, "Rename", RenameItem) ;
  AddTool (6, "Delete", DeleteItem) ;
  pressedButton := -1 ;
  showHidden := FALSE ;
  clipboard[0] := 0C ;
  clipboardCut := FALSE ;
  status[0] := 0C ;
  editingLocation := FALSE ;
  dragging := FALSE ;
  lastRow := -1 ;
  lastClick := 0 ;
  list.rowHeight := Gfx.lineHeight + 6 ;
  win := Win.Create ("Files", "mosaic-files", 720, 480, 480, 300) ;
  Layout ;
  StartFolder (cwd) ;
  IF NOT Enter (cwd, "")
  THEN
    Refresh ("")
  END ;
  IF XMapWindow (dpy, win^.window) = 0 THEN END ;
  running := TRUE ;
  WHILE running DO
    IF XServer.WaitEvent (1000) AND XServer.NextEvent (event)
    THEN
      Dispatch (event)
    END ;
    WHILE Spawn.Reap () > 0 DO END ;
    IF mx_take_signal () # 0
    THEN
      running := FALSE
    END
  END ;
  Fs.Free (listing) ;
  Win.Destroy (win) ;
  Gfx.Done ;
  XServer.Close ;
  exit (0)
END files.
