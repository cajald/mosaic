IMPLEMENTATION MODULE Props ;

FROM SYSTEM IMPORT ADDRESS, ADR ;
FROM Xlib IMPORT Window, Atom, XGetWindowProperty, XChangeProperty, XFree,
                 False, PropModeReplace, XA_STRING, XA_WM_NAME ;
FROM XServer IMPORT dpy ;
IMPORT Atoms, Str ;

CONST
  AnyPropertyType = 0 ;
  MaxLongs = 4096 ;

TYPE
  Longs = POINTER TO ARRAY [0..MaxLongs - 1] OF LONGCARD ;
  Bytes = POINTER TO ARRAY [0..65535] OF CHAR ;

PROCEDURE GetCardinals (w: Window; property, type: Atom;
                        VAR values: ARRAY OF LONGCARD) : CARDINAL ;
VAR
  actualType: Atom ;
  format: INTEGER ;
  nitems, after: LONGCARD ;
  data: ADDRESS ;
  longs: Longs ;
  i, n: CARDINAL ;
BEGIN
  data := NIL ;
  IF XGetWindowProperty (dpy, w, property, 0, VAL (LONGINT, HIGH (values)) + 1,
                         False, type, actualType, format, nitems, after,
                         data) # 0
  THEN
    RETURN 0
  END ;
  n := 0 ;
  IF (data # NIL) AND (actualType = type) AND (format = 32)
  THEN
    longs := data ;
    IF nitems > VAL (LONGCARD, HIGH (values)) + 1
    THEN
      nitems := VAL (LONGCARD, HIGH (values)) + 1
    END ;
    n := VAL (CARDINAL, nitems) ;
    (* xlib widens 32-bit items to longs with sign extension *)
    FOR i := 1 TO n DO
      values[i - 1] := longs^[i - 1] MOD 100000000H
    END
  END ;
  IF data # NIL
  THEN
    IF XFree (data) = 0 THEN END
  END ;
  RETURN n
END GetCardinals ;

PROCEDURE GetCardinal (w: Window; property, type: Atom;
                       VAR value: LONGCARD) : BOOLEAN ;
VAR
  v: ARRAY [0..0] OF LONGCARD ;
BEGIN
  IF GetCardinals (w, property, type, v) = 1
  THEN
    value := v[0] ;
    RETURN TRUE
  END ;
  RETURN FALSE
END GetCardinal ;

PROCEDURE SetCardinals (w: Window; property, type: Atom;
                        VAR values: ARRAY OF LONGCARD; n: CARDINAL) ;
BEGIN
  IF XChangeProperty (dpy, w, property, type, 32, PropModeReplace,
                      ADR (values), n) = 0 THEN END
END SetCardinals ;

PROCEDURE SetCardinal (w: Window; property, type: Atom; value: LONGCARD) ;
VAR
  v: ARRAY [0..0] OF LONGCARD ;
BEGIN
  v[0] := value ;
  SetCardinals (w, property, type, v, 1)
END SetCardinal ;

(* latin-1 to utf-8, stopping before the buffer would overflow *)
PROCEDURE Latin1 (src: Bytes; n: CARDINAL; VAR dst: ARRAY OF CHAR) ;
VAR
  i, j, c: CARDINAL ;
BEGIN
  i := 0 ;
  j := 0 ;
  WHILE (i < n) AND (src^[i] # 0C) DO
    c := ORD (src^[i]) ;
    IF c < 128
    THEN
      IF j + 1 > HIGH (dst) THEN dst[j] := 0C ; RETURN END ;
      dst[j] := CHR (c) ;
      INC (j)
    ELSE
      IF j + 2 > HIGH (dst) THEN dst[j] := 0C ; RETURN END ;
      dst[j] := CHR (192 + c DIV 64) ;
      dst[j + 1] := CHR (128 + c MOD 64) ;
      INC (j, 2)
    END ;
    INC (i)
  END ;
  dst[j] := 0C
END Latin1 ;

PROCEDURE GetText (w: Window; property: Atom;
                   VAR text: ARRAY OF CHAR) : BOOLEAN ;
VAR
  actualType: Atom ;
  format: INTEGER ;
  nitems, after: LONGCARD ;
  data: ADDRESS ;
  ok: BOOLEAN ;
BEGIN
  text[0] := 0C ;
  data := NIL ;
  IF XGetWindowProperty (dpy, w, property, 0, VAL (LONGINT, HIGH (text)) DIV 4 + 1,
                         False, AnyPropertyType, actualType, format, nitems,
                         after, data) # 0
  THEN
    RETURN FALSE
  END ;
  ok := (data # NIL) AND (format = 8) ;
  IF ok
  THEN
    IF actualType = XA_STRING
    THEN
      Latin1 (data, VAL (CARDINAL, nitems), text)
    ELSE
      (* utf8 and compound text share the ascii range *)
      Str.FromBytes (data, VAL (CARDINAL, nitems), text)
    END
  END ;
  IF data # NIL
  THEN
    IF XFree (data) = 0 THEN END
  END ;
  RETURN ok
END GetText ;

PROCEDURE GetTitle (w: Window; VAR title: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  IF GetText (w, Atoms.NetWmName, title) AND (title[0] # 0C)
  THEN
    RETURN TRUE
  END ;
  RETURN GetText (w, XA_WM_NAME, title)
END GetTitle ;

PROCEDURE SetText (w: Window; property: Atom; text: ARRAY OF CHAR) ;
BEGIN
  IF XChangeProperty (dpy, w, property, Atoms.Utf8String, 8, PropModeReplace,
                      ADR (text), Str.Length (text)) = 0 THEN END
END SetText ;

PROCEDURE GetTextList (w: Window; property: Atom;
                       VAR data: ARRAY OF CHAR) : CARDINAL ;
VAR
  actualType: Atom ;
  format: INTEGER ;
  nitems, after: LONGCARD ;
  raw: ADDRESS ;
  bytes: Bytes ;
  i, n: CARDINAL ;
BEGIN
  raw := NIL ;
  IF XGetWindowProperty (dpy, w, property, 0, VAL (LONGINT, HIGH (data)) DIV 4,
                         False, Atoms.Utf8String, actualType, format, nitems,
                         after, raw) # 0
  THEN
    RETURN 0
  END ;
  n := 0 ;
  IF (raw # NIL) AND (format = 8)
  THEN
    bytes := raw ;
    n := VAL (CARDINAL, nitems) ;
    IF n > HIGH (data) THEN n := HIGH (data) END ;
    FOR i := 1 TO n DO
      data[i - 1] := bytes^[i - 1]
    END ;
    data[n] := 0C
  END ;
  IF raw # NIL
  THEN
    IF XFree (raw) = 0 THEN END
  END ;
  RETURN n
END GetTextList ;

PROCEDURE SetTextList (w: Window; property: Atom; VAR data: ARRAY OF CHAR;
                       len: CARDINAL) ;
BEGIN
  IF XChangeProperty (dpy, w, property, Atoms.Utf8String, 8, PropModeReplace,
                      ADR (data), len) = 0 THEN END
END SetTextList ;

END Props.
