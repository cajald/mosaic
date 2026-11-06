IMPLEMENTATION MODULE Widgets ;

FROM Xlib IMPORT KeySym, XBell ;
FROM XServer IMPORT dpy ;
FROM Gfx IMPORT Surface ;
IMPORT Gfx, Str ;

CONST
  LineGap = 3 ;

PROCEDURE Inside (px, py, x, y, w, h: INTEGER) : BOOLEAN ;
BEGIN
  RETURN (px >= x) AND (py >= y) AND (px < x + w) AND (py < y + h)
END Inside ;

PROCEDURE IsEnter (sym: KeySym) : BOOLEAN ;
BEGIN
  RETURN (sym = XKReturn) OR (sym = XKKPEnter)
END IsEnter ;

PROCEDURE SetButton (VAR b: Button; label: ARRAY OF CHAR; x, y, w: INTEGER) ;
BEGIN
  IF NOT Str.Assign (label, b.label)
  THEN
    b.label[0] := 0C
  END ;
  b.x := x ;
  b.y := y ;
  b.w := w ;
  b.h := ButtonHeight ;
  b.down := FALSE ;
  b.isDefault := FALSE
END SetButton ;

PROCEDURE DrawButton (s: Surface; VAR b: Button) ;
VAR
  tw, x, y, w, h: INTEGER ;
BEGIN
  x := b.x ; y := b.y ; w := b.w ; h := b.h ;
  IF b.isDefault
  THEN
    (* the default action carries a second dark ring *)
    Gfx.Outline (s, x - 2, y - 2, w + 4, h + 4, Gfx.Dark)
  END ;
  Gfx.Button (s, x, y, w, h, b.down) ;
  tw := Gfx.TextWidth (b.label, FALSE) ;
  IF tw > w - 8
  THEN
    Gfx.TextClip (s, x + 4, y + (h - Gfx.lineHeight) DIV 2, w - 8, b.label,
                  Gfx.Ink, FALSE)
  ELSE
    Gfx.Text (s, x + (w - tw) DIV 2, y + (h - Gfx.lineHeight) DIV 2,
              b.label, Gfx.Ink, FALSE)
  END
END DrawButton ;

PROCEDURE OnButton (VAR b: Button; px, py: INTEGER) : BOOLEAN ;
BEGIN
  RETURN Inside (px, py, b.x, b.y, b.w, b.h)
END OnButton ;

PROCEDURE SetField (VAR f: TextField; text: ARRAY OF CHAR) ;
BEGIN
  IF NOT Str.Assign (text, f.text)
  THEN
    f.text[0] := 0C
  END ;
  f.cursor := Str.Length (f.text)
END SetField ;

PROCEDURE DrawField (s: Surface; VAR f: TextField) ;
VAR
  start, n: CARDINAL ;
  inner, cx: INTEGER ;
BEGIN
  Gfx.Fill (s, f.x, f.y, f.w, FieldHeight, Gfx.Field) ;
  Gfx.Bevel (s, f.x, f.y, f.w, FieldHeight, FALSE) ;
  Gfx.Outline (s, f.x + 1, f.y + 1, f.w - 2, FieldHeight - 2, Gfx.Dark) ;
  inner := f.w - 10 ;
  n := Str.Length (f.text) ;
  IF f.cursor > n THEN f.cursor := n END ;
  (* scroll right until the cursor is visible *)
  start := 0 ;
  WHILE Gfx.SpanWidth (f.text, start, f.cursor, FALSE) > inner DO
    INC (start) ;
    WHILE (start < f.cursor) AND (ORD (f.text[start]) DIV 64 = 2) DO
      INC (start)
    END
  END ;
  Gfx.TextSpan (s, f.x + 5, f.y + (FieldHeight - Gfx.lineHeight) DIV 2,
                f.text, start, Fit (f.text, start, n, inner), Gfx.Ink, FALSE) ;
  IF f.focused
  THEN
    cx := f.x + 5 + Gfx.SpanWidth (f.text, start, f.cursor, FALSE) ;
    Gfx.Fill (s, cx, f.y + 4, 2, FieldHeight - 8, Gfx.Accent)
  END
END DrawField ;

(* last byte position from start that still fits into width *)
PROCEDURE Fit (VAR text: ARRAY OF CHAR; start, n: CARDINAL;
               width: INTEGER) : CARDINAL ;
VAR
  stop: CARDINAL ;
BEGIN
  stop := n ;
  WHILE (stop > start) AND (Gfx.SpanWidth (text, start, stop, FALSE) > width) DO
    DEC (stop) ;
    WHILE (stop > start) AND (ORD (text[stop]) DIV 64 = 2) DO
      DEC (stop)
    END
  END ;
  RETURN stop
END Fit ;

PROCEDURE PrevChar (VAR text: ARRAY OF CHAR; i: CARDINAL) : CARDINAL ;
BEGIN
  IF i > 0
  THEN
    DEC (i) ;
    WHILE (i > 0) AND (ORD (text[i]) DIV 64 = 2) DO
      DEC (i)
    END
  END ;
  RETURN i
END PrevChar ;

PROCEDURE NextChar (VAR text: ARRAY OF CHAR; i: CARDINAL) : CARDINAL ;
VAR
  n: CARDINAL ;
BEGIN
  n := Str.Length (text) ;
  IF i < n
  THEN
    INC (i) ;
    WHILE (i < n) AND (ORD (text[i]) DIV 64 = 2) DO
      INC (i)
    END
  END ;
  RETURN i
END NextChar ;

PROCEDURE DeleteSpan (VAR text: ARRAY OF CHAR; from, to: CARDINAL) ;
VAR
  n: CARDINAL ;
BEGIN
  n := Str.Length (text) ;
  WHILE to <= n DO
    text[from] := text[to] ;
    INC (from) ;
    INC (to)
  END
END DeleteSpan ;

PROCEDURE Insert (VAR f: TextField; text: ARRAY OF CHAR) : BOOLEAN ;
VAR
  n, m, i: CARDINAL ;
BEGIN
  n := Str.Length (f.text) ;
  m := Str.Length (text) ;
  IF m = 0
  THEN
    RETURN TRUE
  END ;
  IF n + m > HIGH (f.text)
  THEN
    RETURN FALSE
  END ;
  i := n + 1 ;
  WHILE i > f.cursor DO
    DEC (i) ;
    f.text[i + m] := f.text[i]
  END ;
  FOR i := 0 TO m - 1 DO
    f.text[f.cursor + i] := text[i]
  END ;
  INC (f.cursor, m) ;
  RETURN TRUE
END Insert ;

PROCEDURE FieldKey (VAR f: TextField; sym: KeySym;
                    text: ARRAY OF CHAR) : Edit ;
VAR
  p: CARDINAL ;
BEGIN
  IF IsEnter (sym)
  THEN
    RETURN EditEnter
  ELSIF sym = XKEscape
  THEN
    RETURN EditCancel
  ELSIF sym = XKBackSpace
  THEN
    IF f.cursor = 0 THEN RETURN EditNone END ;
    p := PrevChar (f.text, f.cursor) ;
    DeleteSpan (f.text, p, f.cursor) ;
    f.cursor := p ;
    RETURN EditChanged
  ELSIF sym = XKDelete
  THEN
    p := NextChar (f.text, f.cursor) ;
    IF p = f.cursor THEN RETURN EditNone END ;
    DeleteSpan (f.text, f.cursor, p) ;
    RETURN EditChanged
  ELSIF sym = XKLeft
  THEN
    f.cursor := PrevChar (f.text, f.cursor) ;
    RETURN EditMoved
  ELSIF sym = XKRight
  THEN
    f.cursor := NextChar (f.text, f.cursor) ;
    RETURN EditMoved
  ELSIF sym = XKHome
  THEN
    f.cursor := 0 ;
    RETURN EditMoved
  ELSIF sym = XKEnd
  THEN
    f.cursor := Str.Length (f.text) ;
    RETURN EditMoved
  ELSIF (text[0] >= ' ') AND (text[0] # 177C)
  THEN
    IF Insert (f, text)
    THEN
      RETURN EditChanged
    END ;
    (* full: refuse the character audibly rather than drop it quietly *)
    IF XBell (dpy, 0) = 0 THEN END
  END ;
  RETURN EditNone
END FieldKey ;

PROCEDURE ListVisibleRows (VAR l: ListView) : INTEGER ;
VAR
  n: INTEGER ;
BEGIN
  n := (l.h - 4) DIV l.rowHeight ;
  IF n < 1 THEN n := 1 END ;
  RETURN n
END ListVisibleRows ;

PROCEDURE ClampTop (VAR l: ListView) ;
VAR
  limit: INTEGER ;
BEGIN
  limit := l.count - ListVisibleRows (l) ;
  IF limit < 0 THEN limit := 0 END ;
  IF l.top > limit THEN l.top := limit END ;
  IF l.top < 0 THEN l.top := 0 END
END ClampTop ;

PROCEDURE TrackGeometry (VAR l: ListView; VAR trackY, trackH, thumbY,
                         thumbH: INTEGER) ;
VAR
  visible: INTEGER ;
BEGIN
  trackY := l.y + 2 ;
  trackH := l.h - 4 ;
  visible := ListVisibleRows (l) ;
  IF l.count <= visible
  THEN
    thumbY := trackY ;
    thumbH := trackH ;
    RETURN
  END ;
  thumbH := trackH * visible DIV l.count ;
  IF thumbH < 16 THEN thumbH := 16 END ;
  thumbY := trackY + (trackH - thumbH) * l.top DIV (l.count - visible)
END TrackGeometry ;

PROCEDURE DrawList (s: Surface; VAR l: ListView; row: DrawRow) ;
VAR
  i, rx, ry, rw, last: INTEGER ;
  trackY, trackH, thumbY, thumbH, sx: INTEGER ;
BEGIN
  ClampTop (l) ;
  Gfx.Fill (s, l.x, l.y, l.w, l.h, Gfx.Field) ;
  Gfx.Bevel (s, l.x, l.y, l.w, l.h, FALSE) ;
  IF l.focused
  THEN
    Gfx.Outline (s, l.x + 1, l.y + 1, l.w - 2, l.h - 2, Gfx.Accent)
  ELSE
    Gfx.Outline (s, l.x + 1, l.y + 1, l.w - 2, l.h - 2, Gfx.Dark)
  END ;
  rx := l.x + 2 ;
  rw := l.w - 4 - ScrollbarWidth ;
  last := l.top + ListVisibleRows (l) - 1 ;
  IF last >= l.count THEN last := l.count - 1 END ;
  FOR i := l.top TO last DO
    ry := l.y + 2 + (i - l.top) * l.rowHeight ;
    row (s, i, rx, ry, rw, l.rowHeight, i = l.selected)
  END ;
  sx := l.x + l.w - 2 - ScrollbarWidth ;
  TrackGeometry (l, trackY, trackH, thumbY, thumbH) ;
  Gfx.Fill (s, sx, trackY, ScrollbarWidth, trackH, Gfx.Shadow) ;
  Gfx.Line (s, sx, trackY, sx, trackY + trackH - 1, Gfx.Dark) ;
  IF l.count > ListVisibleRows (l)
  THEN
    Gfx.Button (s, sx, thumbY, ScrollbarWidth, thumbH, FALSE) ;
    (* grip lines in the middle of the thumb *)
    Gfx.Line (s, sx + 4, thumbY + thumbH DIV 2 - 2, sx + ScrollbarWidth - 5,
              thumbY + thumbH DIV 2 - 2, Gfx.Shadow) ;
    Gfx.Line (s, sx + 4, thumbY + thumbH DIV 2 + 1, sx + ScrollbarWidth - 5,
              thumbY + thumbH DIV 2 + 1, Gfx.Shadow)
  END
END DrawList ;

PROCEDURE ListRowAt (VAR l: ListView; px, py: INTEGER) : INTEGER ;
VAR
  i: INTEGER ;
BEGIN
  IF NOT Inside (px, py, l.x + 2, l.y + 2, l.w - 4 - ScrollbarWidth, l.h - 4)
  THEN
    RETURN -1
  END ;
  i := l.top + (py - l.y - 2) DIV l.rowHeight ;
  IF i >= l.count
  THEN
    RETURN -1
  END ;
  RETURN i
END ListRowAt ;

PROCEDURE ListOnScrollbar (VAR l: ListView; px, py: INTEGER) : BOOLEAN ;
BEGIN
  RETURN Inside (px, py, l.x + l.w - 2 - ScrollbarWidth, l.y + 2,
                 ScrollbarWidth, l.h - 4)
END ListOnScrollbar ;

PROCEDURE ListDragThumb (VAR l: ListView; py: INTEGER) ;
VAR
  trackY, trackH, thumbY, thumbH, visible: INTEGER ;
BEGIN
  visible := ListVisibleRows (l) ;
  IF l.count <= visible
  THEN
    RETURN
  END ;
  TrackGeometry (l, trackY, trackH, thumbY, thumbH) ;
  IF trackH <= thumbH
  THEN
    RETURN
  END ;
  l.top := (py - trackY - thumbH DIV 2) * (l.count - visible) DIV
           (trackH - thumbH) ;
  ClampTop (l)
END ListDragThumb ;

PROCEDURE ListSelect (VAR l: ListView; index: INTEGER) ;
VAR
  visible: INTEGER ;
BEGIN
  IF l.count = 0
  THEN
    l.selected := -1 ;
    l.top := 0 ;
    RETURN
  END ;
  IF index < 0 THEN index := 0 END ;
  IF index >= l.count THEN index := l.count - 1 END ;
  l.selected := index ;
  visible := ListVisibleRows (l) ;
  IF index < l.top THEN l.top := index END ;
  IF index >= l.top + visible THEN l.top := index - visible + 1 END ;
  ClampTop (l)
END ListSelect ;

PROCEDURE ListScroll (VAR l: ListView; rows: INTEGER) ;
BEGIN
  INC (l.top, rows) ;
  ClampTop (l)
END ListScroll ;

PROCEDURE ListKey (VAR l: ListView; sym: KeySym) : BOOLEAN ;
VAR
  target, page: INTEGER ;
BEGIN
  IF l.count = 0
  THEN
    RETURN FALSE
  END ;
  page := ListVisibleRows (l) - 1 ;
  IF page < 1 THEN page := 1 END ;
  target := l.selected ;
  IF sym = XKUp THEN target := l.selected - 1
  ELSIF sym = XKDown THEN target := l.selected + 1
  ELSIF sym = XKPageUp THEN target := l.selected - page
  ELSIF sym = XKPageDown THEN target := l.selected + page
  ELSIF sym = XKHome THEN target := 0
  ELSIF sym = XKEnd THEN target := l.count - 1
  ELSE
    RETURN FALSE
  END ;
  IF l.selected < 0
  THEN
    target := 0
  END ;
  ListSelect (l, target) ;
  RETURN TRUE
END ListKey ;

(* lay text out in lines no wider than w; draws when s is not NIL *)
PROCEDURE Wrap (s: Surface; x, y, w: INTEGER;
                VAR text: ARRAY OF CHAR) : INTEGER ;
VAR
  n, start, stop, good, next: CARDINAL ;
  lines: INTEGER ;
BEGIN
  n := Str.Length (text) ;
  start := 0 ;
  lines := 0 ;
  WHILE start < n DO
    (* extend word by word while the line fits *)
    good := start ;
    stop := start ;
    LOOP
      WHILE (stop < n) AND (text[stop] # ' ') AND (text[stop] # 12C) DO
        INC (stop)
      END ;
      IF Gfx.SpanWidth (text, start, stop, FALSE) > w
      THEN
        EXIT
      END ;
      good := stop ;
      IF (stop >= n) OR (text[stop] = 12C)
      THEN
        EXIT
      END ;
      INC (stop)
    END ;
    IF (good = start) AND (stop > start)
    THEN
      (* a single word wider than the line breaks anywhere *)
      good := Fit (text, start, stop, w) ;
      IF good = start
      THEN
        good := start + 1 ;
        WHILE (good < n) AND (ORD (text[good]) DIV 64 = 2) DO INC (good) END
      END
    END ;
    IF s # NIL
    THEN
      Gfx.TextSpan (s, x, y + lines * (Gfx.lineHeight + LineGap), text,
                    start, good, Gfx.Ink, FALSE)
    END ;
    INC (lines) ;
    next := good ;
    IF (next < n) AND ((text[next] = ' ') OR (text[next] = 12C))
    THEN
      INC (next)
    END ;
    start := next
  END ;
  IF lines = 0 THEN lines := 1 END ;
  RETURN lines * (Gfx.lineHeight + LineGap)
END Wrap ;

PROCEDURE DrawWrapped (s: Surface; x, y, w: INTEGER;
                       text: ARRAY OF CHAR) : INTEGER ;
BEGIN
  RETURN Wrap (s, x, y, w, text)
END DrawWrapped ;

PROCEDURE WrappedHeight (w: INTEGER; text: ARRAY OF CHAR) : INTEGER ;
BEGIN
  RETURN Wrap (NIL, 0, 0, w, text)
END WrappedHeight ;

PROCEDURE DrawPanel (s: Surface; x, y, w, h: INTEGER) ;
BEGIN
  Gfx.Fill (s, x, y, w, h, Gfx.Face) ;
  Gfx.Bevel (s, x, y, w, h, TRUE)
END DrawPanel ;

END Widgets.
