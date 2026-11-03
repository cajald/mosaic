IMPLEMENTATION MODULE Clients ;

FROM Xlib IMPORT Window, None ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;

PROCEDURE New (w: Window) : Client ;
VAR
  c, last: Client ;
BEGIN
  NEW (c) ;
  c^.window := w ;
  c^.frame := None ;
  c^.kind := Normal ;
  c^.x := 0 ; c^.y := 0 ; c^.width := 1 ; c^.height := 1 ;
  c^.savedX := 0 ; c^.savedY := 0 ; c^.savedWidth := 0 ; c^.savedHeight := 0 ;
  c^.minWidth := 0 ; c^.minHeight := 0 ; c^.maxWidth := 0 ; c^.maxHeight := 0 ;
  c^.incWidth := 0 ; c^.incHeight := 0 ; c^.baseWidth := 0 ; c^.baseHeight := 0 ;
  c^.desktop := 0 ;
  c^.title[0] := 0C ;
  c^.transientFor := None ;
  c^.acceptsInput := TRUE ;
  c^.takeFocus := FALSE ;
  c^.deleteWindow := FALSE ;
  c^.decorated := TRUE ;
  c^.minimized := FALSE ;
  c^.maximized := FALSE ;
  c^.fullscreen := FALSE ;
  c^.urgent := FALSE ;
  c^.strut[0] := 0 ; c^.strut[1] := 0 ; c^.strut[2] := 0 ; c^.strut[3] := 0 ;
  c^.skipTaskbar := FALSE ;
  c^.skipPager := FALSE ;
  c^.next := NIL ;
  (* keep management order for _NET_CLIENT_LIST *)
  IF first = NIL
  THEN
    first := c
  ELSE
    last := first ;
    WHILE last^.next # NIL DO
      last := last^.next
    END ;
    last^.next := c
  END ;
  c^.stackNext := stackTop ;
  stackTop := c ;
  c^.focusNext := focusFirst ;
  focusFirst := c ;
  INC (count) ;
  RETURN c
END New ;

PROCEDURE Unlink (VAR head: Client; c: Client; which: CARDINAL) ;
VAR
  p: Client ;
BEGIN
  IF head = c
  THEN
    CASE which OF
      0: head := c^.next |
      1: head := c^.stackNext |
      2: head := c^.focusNext
    END ;
    RETURN
  END ;
  p := head ;
  WHILE p # NIL DO
    CASE which OF
      0: IF p^.next = c THEN p^.next := c^.next ; RETURN END ;
         p := p^.next |
      1: IF p^.stackNext = c THEN p^.stackNext := c^.stackNext ; RETURN END ;
         p := p^.stackNext |
      2: IF p^.focusNext = c THEN p^.focusNext := c^.focusNext ; RETURN END ;
         p := p^.focusNext
    END
  END
END Unlink ;

PROCEDURE Remove (c: Client) ;
BEGIN
  Unlink (first, c, 0) ;
  Unlink (stackTop, c, 1) ;
  Unlink (focusFirst, c, 2) ;
  DEC (count) ;
  DISPOSE (c)
END Remove ;

PROCEDURE Find (w: Window) : Client ;
VAR
  c: Client ;
BEGIN
  c := first ;
  WHILE (c # NIL) AND (c^.window # w) DO
    c := c^.next
  END ;
  RETURN c
END Find ;

PROCEDURE FindFrame (w: Window) : Client ;
VAR
  c: Client ;
BEGIN
  c := first ;
  WHILE (c # NIL) AND ((c^.frame # w) OR (w = None)) DO
    c := c^.next
  END ;
  RETURN c
END FindFrame ;

PROCEDURE Raise (c: Client) ;
BEGIN
  Unlink (stackTop, c, 1) ;
  c^.stackNext := stackTop ;
  stackTop := c
END Raise ;

PROCEDURE Lower (c: Client) ;
VAR
  p: Client ;
BEGIN
  Unlink (stackTop, c, 1) ;
  c^.stackNext := NIL ;
  IF stackTop = NIL
  THEN
    stackTop := c
  ELSE
    p := stackTop ;
    WHILE p^.stackNext # NIL DO
      p := p^.stackNext
    END ;
    p^.stackNext := c
  END
END Lower ;

PROCEDURE Touch (c: Client) ;
BEGIN
  Unlink (focusFirst, c, 2) ;
  c^.focusNext := focusFirst ;
  focusFirst := c
END Touch ;

BEGIN
  first := NIL ;
  stackTop := NIL ;
  focusFirst := NIL ;
  count := 0
END Clients.
