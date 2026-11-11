IMPLEMENTATION MODULE Gfx ;

FROM SYSTEM IMPORT ADDRESS, ADR ;
FROM Xlib IMPORT Window, GC, XCreateGC, XFreeGC, XSetForeground,
                 XFillRectangle, XDrawLine, XDrawRectangle, XCreatePixmap,
                 XFreePixmap, XCopyArea ;
FROM Xft IMPORT XftFontPtr, XftColor, XGlyphInfo, XftFontOpenName,
                XftFontClose, XftDrawCreate, XftDrawChange, XftDrawDestroy,
                XftColorAllocName, XftColorFree, XftDrawStringUtf8,
                XftTextExtentsUtf8 ;
FROM XServer IMPORT dpy, screen, root, visual, colormap, depth ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
IMPORT Config, Str, Log ;

CONST
  Ellipsis = "…" ;

VAR
  colors: ARRAY Color OF XftColor ;
  allocated: ARRAY Color OF BOOLEAN ;
  gc: GC ;

PROCEDURE LoadColor (c: Color; key, default: ARRAY OF CHAR) ;
VAR
  name: ARRAY [0..63] OF CHAR ;
BEGIN
  Config.Get (key, default, name) ;
  IF XftColorAllocName (dpy, visual, colormap, name, colors[c]) = 0
  THEN
    Log.Error2 ("unknown color, using default", name) ;
    IF XftColorAllocName (dpy, visual, colormap, default, colors[c]) = 0
    THEN
      colors[c].pixel := 0 ;
      RETURN
    END
  END ;
  allocated[c] := TRUE
END LoadColor ;

PROCEDURE OpenFont (key, default: ARRAY OF CHAR) : XftFontPtr ;
VAR
  name: ARRAY [0..127] OF CHAR ;
  f: XftFontPtr ;
BEGIN
  Config.Get (key, default, name) ;
  f := XftFontOpenName (dpy, screen, name) ;
  IF f = NIL
  THEN
    Log.Error2 ("cannot open font, using default", name) ;
    f := XftFontOpenName (dpy, screen, default)
  END ;
  RETURN f
END OpenFont ;

PROCEDURE Init () : BOOLEAN ;
VAR
  c: Color ;
BEGIN
  FOR c := MIN (Color) TO MAX (Color) DO
    allocated[c] := FALSE
  END ;
  LoadColor (Desk, "color.desktop", "#5d7078") ;
  LoadColor (DeskTile, "color.desktop.tile", "#53656c") ;
  LoadColor (Face, "color.face", "#c9c5bc") ;
  LoadColor (Light, "color.light", "#f2efe8") ;
  LoadColor (Shadow, "color.shadow", "#8b877e") ;
  LoadColor (Dark, "color.dark", "#1e1e1e") ;
  LoadColor (Ink, "color.text", "#121212") ;
  LoadColor (InkDim, "color.text.dim", "#6b675f") ;
  LoadColor (Accent, "color.active", "#2e4a66") ;
  LoadColor (AccentInk, "color.active.text", "#ffffff") ;
  LoadColor (Idle, "color.inactive", "#a9a59c") ;
  LoadColor (IdleInk, "color.inactive.text", "#34322e") ;
  LoadColor (Field, "color.field", "#fbfaf6") ;
  LoadColor (Select, "color.selection", "#2e4a66") ;
  LoadColor (SelectInk, "color.selection.text", "#ffffff") ;
  LoadColor (Alert, "color.alert", "#b5832a") ;
  font := OpenFont ("font", "DejaVu Sans:size=9") ;
  bold := OpenFont ("font.bold", "DejaVu Sans:size=9:bold") ;
  IF (font = NIL) OR (bold = NIL)
  THEN
    Log.Error ("no usable font found") ;
    RETURN FALSE
  END ;
  lineHeight := font^.ascent + font^.descent ;
  gc := XCreateGC (dpy, root, 0, NIL) ;
  RETURN TRUE
END Init ;

PROCEDURE Done ;
VAR
  c: Color ;
BEGIN
  FOR c := MIN (Color) TO MAX (Color) DO
    IF allocated[c]
    THEN
      XftColorFree (dpy, visual, colormap, colors[c]) ;
      allocated[c] := FALSE
    END
  END ;
  IF font # NIL THEN XftFontClose (dpy, font) ; font := NIL END ;
  IF bold # NIL THEN XftFontClose (dpy, bold) ; bold := NIL END ;
  IF gc # NIL
  THEN
    IF XFreeGC (dpy, gc) = 0 THEN END ;
    gc := NIL
  END
END Done ;

PROCEDURE Pixel (c: Color) : LONGCARD ;
BEGIN
  RETURN colors[c].pixel
END Pixel ;

PROCEDURE NewSurface (w: Window; buffered: BOOLEAN) : Surface ;
VAR
  s: Surface ;
BEGIN
  NEW (s) ;
  s^.window := w ;
  s^.target := w ;
  s^.width := 0 ;
  s^.height := 0 ;
  s^.buffered := buffered ;
  s^.draw := XftDrawCreate (dpy, w, visual, colormap) ;
  RETURN s
END NewSurface ;

PROCEDURE Resize (s: Surface; width, height: INTEGER) ;
BEGIN
  IF width < 1 THEN width := 1 END ;
  IF height < 1 THEN height := 1 END ;
  IF (width = s^.width) AND (height = s^.height)
  THEN
    RETURN
  END ;
  s^.width := width ;
  s^.height := height ;
  IF s^.buffered
  THEN
    IF s^.target # s^.window
    THEN
      IF XFreePixmap (dpy, s^.target) = 0 THEN END
    END ;
    s^.target := XCreatePixmap (dpy, s^.window, width, height, depth) ;
    XftDrawChange (s^.draw, s^.target)
  END
END Resize ;

PROCEDURE FreeSurface (VAR s: Surface) ;
BEGIN
  IF s = NIL
  THEN
    RETURN
  END ;
  XftDrawDestroy (s^.draw) ;
  IF s^.target # s^.window
  THEN
    IF XFreePixmap (dpy, s^.target) = 0 THEN END
  END ;
  DISPOSE (s) ;
  s := NIL
END FreeSurface ;

PROCEDURE Flush (s: Surface) ;
BEGIN
  IF s^.target # s^.window
  THEN
    IF XCopyArea (dpy, s^.target, s^.window, gc, 0, 0, s^.width, s^.height,
                  0, 0) = 0 THEN END
  END
END Flush ;

PROCEDURE Fill (s: Surface; x, y, w, h: INTEGER; c: Color) ;
BEGIN
  IF (w > 0) AND (h > 0)
  THEN
    IF XSetForeground (dpy, gc, colors[c].pixel) = 0 THEN END ;
    IF XFillRectangle (dpy, s^.target, gc, x, y, w, h) = 0 THEN END
  END
END Fill ;

PROCEDURE Outline (s: Surface; x, y, w, h: INTEGER; c: Color) ;
BEGIN
  IF (w > 1) AND (h > 1)
  THEN
    IF XSetForeground (dpy, gc, colors[c].pixel) = 0 THEN END ;
    IF XDrawRectangle (dpy, s^.target, gc, x, y, w - 1, h - 1) = 0 THEN END
  END
END Outline ;

PROCEDURE Line (s: Surface; x1, y1, x2, y2: INTEGER; c: Color) ;
BEGIN
  IF XSetForeground (dpy, gc, colors[c].pixel) = 0 THEN END ;
  IF XDrawLine (dpy, s^.target, gc, x1, y1, x2, y2) = 0 THEN END
END Line ;

PROCEDURE Bevel (s: Surface; x, y, w, h: INTEGER; raised: BOOLEAN) ;
VAR
  tl, br: Color ;
BEGIN
  IF raised
  THEN
    tl := Light ; br := Shadow
  ELSE
    tl := Shadow ; br := Light
  END ;
  Line (s, x, y, x + w - 2, y, tl) ;
  Line (s, x, y, x, y + h - 2, tl) ;
  Line (s, x + w - 1, y, x + w - 1, y + h - 1, br) ;
  Line (s, x, y + h - 1, x + w - 1, y + h - 1, br)
END Bevel ;

PROCEDURE Button (s: Surface; x, y, w, h: INTEGER; pressed: BOOLEAN) ;
BEGIN
  Outline (s, x, y, w, h, Dark) ;
  IF pressed
  THEN
    Fill (s, x + 1, y + 1, w - 2, h - 2, Shadow) ;
    Bevel (s, x + 1, y + 1, w - 2, h - 2, FALSE)
  ELSE
    Fill (s, x + 1, y + 1, w - 2, h - 2, Face) ;
    Bevel (s, x + 1, y + 1, w - 2, h - 2, TRUE)
  END
END Button ;

PROCEDURE FontOf (strong: BOOLEAN) : XftFontPtr ;
BEGIN
  IF strong THEN RETURN bold END ;
  RETURN font
END FontOf ;

PROCEDURE DrawBytes (s: Surface; x, y: INTEGER; p: ADDRESS; n: CARDINAL;
                     c: Color; strong: BOOLEAN) ;
BEGIN
  IF n > 0
  THEN
    XftDrawStringUtf8 (s^.draw, colors[c], FontOf (strong), x,
                       y + font^.ascent, p, n)
  END
END DrawBytes ;

PROCEDURE BytesWidth (p: ADDRESS; n: CARDINAL; strong: BOOLEAN) : INTEGER ;
VAR
  g: XGlyphInfo ;
BEGIN
  IF n = 0
  THEN
    RETURN 0
  END ;
  XftTextExtentsUtf8 (dpy, FontOf (strong), p, n, g) ;
  RETURN VAL (INTEGER, g.xOff)
END BytesWidth ;

PROCEDURE Text (s: Surface; x, y: INTEGER; text: ARRAY OF CHAR; c: Color;
                strong: BOOLEAN) ;
BEGIN
  DrawBytes (s, x, y, ADR (text), Str.Length (text), c, strong)
END Text ;

PROCEDURE TextWidth (text: ARRAY OF CHAR; strong: BOOLEAN) : INTEGER ;
BEGIN
  RETURN BytesWidth (ADR (text), Str.Length (text), strong)
END TextWidth ;

PROCEDURE SpanWidth (VAR text: ARRAY OF CHAR; from, to: CARDINAL;
                     strong: BOOLEAN) : INTEGER ;
BEGIN
  IF to <= from
  THEN
    RETURN 0
  END ;
  RETURN BytesWidth (ADR (text[from]), to - from, strong)
END SpanWidth ;

PROCEDURE TextSpan (s: Surface; x, y: INTEGER; VAR text: ARRAY OF CHAR;
                    from, to: CARDINAL; c: Color; strong: BOOLEAN) ;
BEGIN
  IF to > from
  THEN
    DrawBytes (s, x, y, ADR (text[from]), to - from, c, strong)
  END
END TextSpan ;

PROCEDURE TextClip (s: Surface; x, y, maxWidth: INTEGER;
                    text: ARRAY OF CHAR; c: Color; strong: BOOLEAN) ;
VAR
  n, lo, hi, mid: CARDINAL ;
  room: INTEGER ;
BEGIN
  n := Str.Length (text) ;
  IF BytesWidth (ADR (text), n, strong) <= maxWidth
  THEN
    DrawBytes (s, x, y, ADR (text), n, c, strong) ;
    RETURN
  END ;
  room := maxWidth - TextWidth (Ellipsis, strong) ;
  IF room <= 0
  THEN
    RETURN
  END ;
  (* longest prefix that fits, found by bisection on byte length *)
  lo := 0 ;
  hi := n ;
  WHILE lo < hi DO
    mid := (lo + hi + 1) DIV 2 ;
    IF BytesWidth (ADR (text), mid, strong) <= room
    THEN
      lo := mid
    ELSE
      hi := mid - 1
    END
  END ;
  WHILE (lo > 0) AND (ORD (text[lo]) DIV 64 = 2) DO
    DEC (lo)
  END ;
  DrawBytes (s, x, y, ADR (text), lo, c, strong) ;
  Text (s, x + BytesWidth (ADR (text), lo, strong), y, Ellipsis, c, strong)
END TextClip ;

BEGIN
  font := NIL ;
  bold := NIL ;
  gc := NIL ;
  lineHeight := 12
END Gfx.
