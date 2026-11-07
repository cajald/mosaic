IMPLEMENTATION MODULE Menu ;

FROM SYSTEM IMPORT ADR ;
FROM Xlib IMPORT Time, KeySym, None, CurrentTime, False, True, XMapRaised,
                 XGrabPointer, XUngrabPointer, XGrabKeyboard,
                 XUngrabKeyboard, GrabModeAsync, GrabSuccess,
                 ButtonPressMask, ButtonReleaseMask, PointerMotionMask,
                 Expose, MotionNotify, ButtonPress, ButtonRelease, KeyPress ;
FROM XGlue IMPORT Event ;
FROM Posix IMPORT mx_signal_pending ;
FROM XServer IMPORT dpy, root, width, height ;
FROM Win IMPORT Handle ;
FROM Gfx IMPORT Surface ;
IMPORT Win, Gfx, Str, Widgets, XServer ;

CONST
  RowHeight = 20 ;
  SeparatorHeight = 7 ;
  Pad = 3 ;
  MaxWidth = 420 ;
  ClickTime = 300 ;

PROCEDURE Clear (VAR m: Menu) ;
BEGIN
  m.count := 0
END Clear ;

PROCEDURE AddItem (VAR m: Menu; label: ARRAY OF CHAR; enabled,
                   checked: BOOLEAN) ;
BEGIN
  IF m.count = MaxItems
  THEN
    RETURN
  END ;
  IF NOT Str.Assign (label, m.items[m.count].label)
  THEN
    (* only shown on screen, so a shortened label is acceptable *)
    Str.FromBytes (ADR (label), Str.Length (label), m.items[m.count].label)
  END ;
  m.items[m.count].enabled := enabled ;
  m.items[m.count].checked := checked ;
  INC (m.count)
END AddItem ;

PROCEDURE Add (VAR m: Menu; label: ARRAY OF CHAR; enabled: BOOLEAN) ;
BEGIN
  AddItem (m, label, enabled, FALSE)
END Add ;

PROCEDURE AddChecked (VAR m: Menu; label: ARRAY OF CHAR; checked: BOOLEAN) ;
BEGIN
  AddItem (m, label, TRUE, checked)
END AddChecked ;

PROCEDURE AddSeparator (VAR m: Menu) ;
BEGIN
  AddItem (m, Separator, FALSE, FALSE)
END AddSeparator ;

PROCEDURE IsSeparator (VAR m: Menu; i: CARDINAL) : BOOLEAN ;
BEGIN
  RETURN Str.Equal (m.items[i].label, Separator)
END IsSeparator ;

PROCEDURE ItemHeight (VAR m: Menu; i: CARDINAL) : INTEGER ;
BEGIN
  IF IsSeparator (m, i) THEN RETURN SeparatorHeight END ;
  RETURN RowHeight
END ItemHeight ;

PROCEDURE ItemAt (VAR m: Menu; w, px, py: INTEGER) : INTEGER ;
VAR
  i: CARDINAL ;
  y: INTEGER ;
BEGIN
  IF (px < 0) OR (px >= w)
  THEN
    RETURN -1
  END ;
  y := Pad ;
  FOR i := 1 TO m.count DO
    IF (py >= y) AND (py < y + ItemHeight (m, i - 1))
    THEN
      IF IsSeparator (m, i - 1) OR NOT m.items[i - 1].enabled
      THEN
        RETURN -1
      END ;
      RETURN i - 1
    END ;
    INC (y, ItemHeight (m, i - 1))
  END ;
  RETURN -1
END ItemAt ;

PROCEDURE Draw (VAR m: Menu; h: Handle; hot: INTEGER) ;
VAR
  s: Surface ;
  i: CARDINAL ;
  y, w: INTEGER ;
  ink: Gfx.Color ;
BEGIN
  s := h^.surface ;
  w := h^.width ;
  Gfx.Fill (s, 0, 0, w, h^.height, Gfx.Face) ;
  Gfx.Outline (s, 0, 0, w, h^.height, Gfx.Dark) ;
  Gfx.Bevel (s, 1, 1, w - 2, h^.height - 2, TRUE) ;
  y := Pad ;
  FOR i := 1 TO m.count DO
    IF IsSeparator (m, i - 1)
    THEN
      Gfx.Line (s, 6, y + 3, w - 7, y + 3, Gfx.Shadow) ;
      Gfx.Line (s, 6, y + 4, w - 7, y + 4, Gfx.Light)
    ELSE
      ink := Gfx.Ink ;
      IF NOT m.items[i - 1].enabled
      THEN
        ink := Gfx.InkDim
      ELSIF VAL (INTEGER, i - 1) = hot
      THEN
        Gfx.Fill (s, 3, y, w - 6, RowHeight, Gfx.Select) ;
        ink := Gfx.SelectInk
      END ;
      IF m.items[i - 1].checked
      THEN
        Gfx.Fill (s, 8, y + 7, 6, 6, ink)
      END ;
      Gfx.TextClip (s, 20, y + (RowHeight - Gfx.lineHeight) DIV 2, w - 30,
                    m.items[i - 1].label, ink, FALSE)
    END ;
    INC (y, ItemHeight (m, i - 1))
  END ;
  Gfx.Flush (s)
END Draw ;

(* next selectable item from i in direction step, or i itself *)
PROCEDURE Step (VAR m: Menu; i, step: INTEGER) : INTEGER ;
VAR
  j, k: INTEGER ;
BEGIN
  j := i ;
  FOR k := 1 TO VAL (INTEGER, m.count) DO
    j := (j + step + VAL (INTEGER, m.count)) MOD VAL (INTEGER, m.count) ;
    IF (NOT IsSeparator (m, j)) AND m.items[j].enabled
    THEN
      RETURN j
    END
  END ;
  RETURN i
END Step ;

PROCEDURE Popup (VAR m: Menu; x, y: INTEGER; t: Time;
                 other: Dispatch) : INTEGER ;
VAR
  h: Handle ;
  e: Event ;
  i: CARDINAL ;
  w, ht, hot, choice, item: INTEGER ;
  sym: KeySym ;
  text: ARRAY [0..15] OF CHAR ;
  done: BOOLEAN ;
  opened: Time ;
BEGIN
  IF m.count = 0
  THEN
    RETURN -1
  END ;
  w := 120 ;
  ht := 2 * Pad ;
  FOR i := 1 TO m.count DO
    IF Gfx.TextWidth (m.items[i - 1].label, FALSE) + 40 > w
    THEN
      w := Gfx.TextWidth (m.items[i - 1].label, FALSE) + 40
    END ;
    INC (ht, ItemHeight (m, i - 1))
  END ;
  IF w > MaxWidth THEN w := MaxWidth END ;
  (* keep the whole menu on screen *)
  IF x + w > width THEN x := width - w END ;
  IF y + ht > height THEN y := height - ht END ;
  IF x < 0 THEN x := 0 END ;
  IF y < 0 THEN y := 0 END ;
  h := Win.CreatePopup (x, y, w, ht) ;
  IF XMapRaised (dpy, h^.window) = 0 THEN END ;
  IF (XGrabPointer (dpy, h^.window, False, ButtonPressMask + ButtonReleaseMask +
                    PointerMotionMask, GrabModeAsync, GrabModeAsync, None, None,
                    t) # GrabSuccess) OR
     (XGrabKeyboard (dpy, h^.window, True, GrabModeAsync, GrabModeAsync,
                     t) # GrabSuccess)
  THEN
    IF XUngrabPointer (dpy, t) = 0 THEN END ;
    Win.Destroy (h) ;
    RETURN -1
  END ;
  opened := t ;
  hot := -1 ;
  choice := -1 ;
  done := FALSE ;
  Draw (m, h, hot) ;
  WHILE NOT done DO
    IF mx_signal_pending () # 0
    THEN
      done := TRUE
    ELSIF NOT (XServer.WaitEvent (1000) AND XServer.NextEvent (e))
    THEN
      e.window := None
    ELSIF e.window # h^.window
    THEN
      other (e)
    ELSE
      CASE e.type OF
        Expose:
          IF e.detail = 0 THEN Draw (m, h, hot) END |
        MotionNotify:
          item := ItemAt (m, w, e.x, e.y) ;
          IF item # hot
          THEN
            hot := item ;
            Draw (m, h, hot)
          END |
        ButtonPress:
          IF NOT Widgets.Inside (e.x, e.y, 0, 0, w, ht)
          THEN
            done := TRUE
          END |
        ButtonRelease:
          item := ItemAt (m, w, e.x, e.y) ;
          IF item >= 0
          THEN
            choice := item ;
            done := TRUE
          ELSIF (e.time - opened > ClickTime) AND
                NOT Widgets.Inside (e.x, e.y, 0, 0, w, ht)
          THEN
            (* press-drag-release that ended outside the menu *)
            done := TRUE
          END |
        KeyPress:
          Win.Key (h, e, sym, text) ;
          IF sym = Widgets.XKEscape
          THEN
            done := TRUE
          ELSIF sym = Widgets.XKDown
          THEN
            hot := Step (m, hot, 1) ;
            Draw (m, h, hot)
          ELSIF sym = Widgets.XKUp
          THEN
            IF hot < 0 THEN hot := 0 END ;
            hot := Step (m, hot, -1) ;
            Draw (m, h, hot)
          ELSIF Widgets.IsEnter (sym) AND (hot >= 0)
          THEN
            choice := hot ;
            done := TRUE
          END
      ELSE
      END
    END
  END ;
  IF XUngrabPointer (dpy, CurrentTime) = 0 THEN END ;
  IF XUngrabKeyboard (dpy, CurrentTime) = 0 THEN END ;
  Win.Destroy (h) ;
  RETURN choice
END Popup ;

END Menu.
