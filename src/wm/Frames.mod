IMPLEMENTATION MODULE Frames ;

FROM Xlib IMPORT XCreateSimpleWindow, XDestroyWindow, XReparentWindow,
                 XSelectInput, XAddToSaveSet, XRemoveFromSaveSet,
                 XMoveResizeWindow, XSetWindowBackground,
                 XSetWindowBorderWidth, XMapWindow, XA_CARDINAL,
                 SubstructureRedirectMask, SubstructureNotifyMask,
                 ButtonPressMask, ButtonReleaseMask, ExposureMask,
                 PointerMotionMask ;
FROM XGlue IMPORT mx_send_configure_notify ;
FROM XServer IMPORT dpy, root ;
FROM Clients IMPORT Client ;
FROM Gfx IMPORT Color, Surface ;
IMPORT Props, Atoms, Gfx ;

CONST
  FrameMask = SubstructureRedirectMask + SubstructureNotifyMask +
              ButtonPressMask + ButtonReleaseMask + ExposureMask +
              PointerMotionMask ;
  MinWidth = 32 ;
  MinHeight = 16 ;
  BoxSize = 16 ;
  BoxGap = 2 ;
  Corner = 20 ;

VAR
  pressedClient: Client ;
  pressedPart: Part ;

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
  IF XSetWindowBackground (dpy, c^.frame, Gfx.Pixel (Gfx.Face)) = 0 THEN END ;
  IF XSetWindowBorderWidth (dpy, c^.window, 0) = 0 THEN END ;
  IF XAddToSaveSet (dpy, c^.window) = 0 THEN END ;
  IF XReparentWindow (dpy, c^.window, c^.frame, Left (c), Top (c)) = 0 THEN END ;
  IF XMapWindow (dpy, c^.window) = 0 THEN END ;
  c^.surface := Gfx.NewSurface (c^.frame, FALSE) ;
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
  IF pressedClient = c
  THEN
    pressedClient := NIL
  END ;
  Gfx.FreeSurface (c^.surface) ;
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

PROCEDURE FrameWidth (c: Client) : INTEGER ;
BEGIN
  RETURN c^.width + ExtraWidth (c)
END FrameWidth ;

PROCEDURE FrameHeight (c: Client) : INTEGER ;
BEGIN
  RETURN c^.height + ExtraHeight (c)
END FrameHeight ;

(* a window whose size hints pin it has nothing to maximize *)
PROCEDURE Resizable (c: Client) : BOOLEAN ;
BEGIN
  RETURN NOT ((c^.maxWidth > 0) AND (c^.maxWidth = c^.minWidth) AND
              (c^.maxHeight > 0) AND (c^.maxHeight = c^.minHeight))
END Resizable ;

PROCEDURE BoxX (c: Client; part: Part) : INTEGER ;
VAR
  right: INTEGER ;
BEGIN
  right := FrameWidth (c) - Border - BoxGap - BoxSize ;
  CASE part OF
    CloseBox: RETURN Border + BoxGap |
    MaximizeBox: RETURN right |
    MinimizeBox:
      IF Resizable (c) THEN RETURN right - BoxGap - BoxSize END ;
      RETURN right
  ELSE
    RETURN 0
  END
END BoxX ;

PROCEDURE DrawBox (c: Client; part: Part) ;
VAR
  s: Surface ;
  x, y: INTEGER ;
  down: BOOLEAN ;
BEGIN
  s := c^.surface ;
  x := BoxX (c, part) ;
  y := Border + (TitleHeight - BoxSize) DIV 2 ;
  down := (pressedClient = c) AND (pressedPart = part) ;
  Gfx.Button (s, x, y, BoxSize, BoxSize, down) ;
  CASE part OF
    CloseBox:
      Gfx.Line (s, x + 5, y + 5, x + 10, y + 10, Gfx.Ink) ;
      Gfx.Line (s, x + 5, y + 10, x + 10, y + 5, Gfx.Ink) ;
      Gfx.Line (s, x + 6, y + 5, x + 11, y + 10, Gfx.Ink) ;
      Gfx.Line (s, x + 6, y + 10, x + 11, y + 5, Gfx.Ink) |
    MinimizeBox:
      Gfx.Fill (s, x + 5, y + 10, 6, 2, Gfx.Ink) |
    MaximizeBox:
      Gfx.Outline (s, x + 4, y + 4, 8, 8, Gfx.Ink) ;
      Gfx.Line (s, x + 4, y + 5, x + 11, y + 5, Gfx.Ink)
  ELSE
  END
END DrawBox ;

PROCEDURE Draw (c: Client; active: BOOLEAN) ;
VAR
  s: Surface ;
  w, h, left, right, tw: INTEGER ;
  band, ink: Color ;
BEGIN
  IF (NOT HasDecor (c)) OR (c^.surface = NIL)
  THEN
    RETURN
  END ;
  s := c^.surface ;
  w := FrameWidth (c) ;
  h := FrameHeight (c) ;
  IF active
  THEN
    band := Gfx.Accent ; ink := Gfx.AccentInk
  ELSE
    band := Gfx.Idle ; ink := Gfx.IdleInk
  END ;
  (* border ring with resize notches near the corners *)
  Gfx.Fill (s, 0, 0, w, Border, Gfx.Face) ;
  Gfx.Fill (s, 0, h - Border, w, Border, Gfx.Face) ;
  Gfx.Fill (s, 0, 0, Border, h, Gfx.Face) ;
  Gfx.Fill (s, w - Border, 0, Border, h, Gfx.Face) ;
  Gfx.Outline (s, 0, 0, w, h, Gfx.Dark) ;
  Gfx.Bevel (s, 1, 1, w - 2, h - 2, TRUE) ;
  Gfx.Line (s, Corner, 1, Corner, Border - 1, Gfx.Shadow) ;
  Gfx.Line (s, w - Corner - 1, 1, w - Corner - 1, Border - 1, Gfx.Shadow) ;
  Gfx.Line (s, Corner, h - Border, Corner, h - 2, Gfx.Shadow) ;
  Gfx.Line (s, w - Corner - 1, h - Border, w - Corner - 1, h - 2, Gfx.Shadow) ;
  Gfx.Line (s, 1, Corner, Border - 1, Corner, Gfx.Shadow) ;
  Gfx.Line (s, 1, h - Corner - 1, Border - 1, h - Corner - 1, Gfx.Shadow) ;
  Gfx.Line (s, w - Border, Corner, w - 2, Corner, Gfx.Shadow) ;
  Gfx.Line (s, w - Border, h - Corner - 1, w - 2, h - Corner - 1, Gfx.Shadow) ;
  (* title band framed in dark lines *)
  Gfx.Fill (s, Border, Border, w - 2 * Border, TitleHeight, band) ;
  Gfx.Outline (s, Border - 1, Border - 1, w - 2 * Border + 2,
               h - 2 * Border + 2, Gfx.Dark) ;
  Gfx.Line (s, Border, Border + TitleHeight - 1, w - Border - 1,
            Border + TitleHeight - 1, Gfx.Dark) ;
  DrawBox (c, CloseBox) ;
  DrawBox (c, MinimizeBox) ;
  IF Resizable (c)
  THEN
    DrawBox (c, MaximizeBox)
  END ;
  left := BoxX (c, CloseBox) + BoxSize + 8 ;
  right := BoxX (c, MinimizeBox) - 8 ;
  IF right > left
  THEN
    tw := Gfx.TextWidth (c^.title, TRUE) ;
    IF tw < right - left
    THEN
      left := left + (right - left - tw) DIV 2
    END ;
    Gfx.TextClip (s, left, Border + (TitleHeight - 1 - Gfx.lineHeight) DIV 2,
                  right - left, c^.title, ink, TRUE)
  END
END Draw ;

PROCEDURE SetPressed (c: Client; part: Part) ;
VAR
  old: Client ;
  oldPart: Part ;
BEGIN
  old := pressedClient ;
  oldPart := pressedPart ;
  pressedClient := c ;
  pressedPart := part ;
  IF (old # NIL) AND ((old # c) OR (oldPart # part))
  THEN
    DrawBox (old, oldPart)
  END ;
  IF (c # NIL) AND (part # Nowhere)
  THEN
    DrawBox (c, part)
  END
END SetPressed ;

PROCEDURE Within (x, y, bx, by, size: INTEGER) : BOOLEAN ;
BEGIN
  RETURN (x >= bx) AND (x < bx + size) AND (y >= by) AND (y < by + size)
END Within ;

PROCEDURE HitTest (c: Client; x, y: INTEGER) : Part ;
VAR
  w, h, boxY: INTEGER ;
  north, south, east, west: BOOLEAN ;
BEGIN
  IF NOT HasDecor (c)
  THEN
    RETURN Nowhere
  END ;
  w := FrameWidth (c) ;
  h := FrameHeight (c) ;
  IF (x < 0) OR (y < 0) OR (x >= w) OR (y >= h)
  THEN
    RETURN Nowhere
  END ;
  north := y < Border ;
  south := y >= h - Border ;
  west := x < Border ;
  east := x >= w - Border ;
  IF north OR south OR west OR east
  THEN
    (* the notched corner zones resize both ways *)
    IF (north OR south) AND (x < Corner) THEN west := TRUE END ;
    IF (north OR south) AND (x >= w - Corner) THEN east := TRUE END ;
    IF (west OR east) AND (y < Corner) THEN north := TRUE END ;
    IF (west OR east) AND (y >= h - Corner) THEN south := TRUE END ;
    IF north AND west THEN RETURN EdgeNW END ;
    IF north AND east THEN RETURN EdgeNE END ;
    IF south AND west THEN RETURN EdgeSW END ;
    IF south AND east THEN RETURN EdgeSE END ;
    IF north THEN RETURN EdgeN END ;
    IF south THEN RETURN EdgeS END ;
    IF west THEN RETURN EdgeW END ;
    RETURN EdgeE
  END ;
  IF y >= Border + TitleHeight
  THEN
    RETURN Nowhere
  END ;
  boxY := Border + (TitleHeight - BoxSize) DIV 2 ;
  IF Within (x, y, BoxX (c, CloseBox), boxY, BoxSize) THEN RETURN CloseBox END ;
  IF Within (x, y, BoxX (c, MinimizeBox), boxY, BoxSize) THEN RETURN MinimizeBox END ;
  IF Resizable (c) AND Within (x, y, BoxX (c, MaximizeBox), boxY, BoxSize)
  THEN
    RETURN MaximizeBox
  END ;
  RETURN TitleBar
END HitTest ;

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

BEGIN
  pressedClient := NIL ;
  pressedPart := Nowhere
END Frames.
