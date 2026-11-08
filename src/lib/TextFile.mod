IMPLEMENTATION MODULE TextFile ;

FROM SYSTEM IMPORT ADR ;
FROM libc IMPORT open, read, close ;
FROM Posix IMPORT OREADONLY, OCLOEXEC, EINTR, mx_errno ;

PROCEDURE Read (path: ARRAY OF CHAR; VAR buf: ARRAY OF CHAR;
                VAR len: CARDINAL) : INTEGER ;
VAR
  fd, n, err: INTEGER ;
  room: CARDINAL ;
BEGIN
  len := 0 ;
  buf[0] := 0C ;
  fd := open (ADR (path), OREADONLY + OCLOEXEC, 0) ;
  IF fd < 0
  THEN
    RETURN mx_errno ()
  END ;
  room := HIGH (buf) ;
  err := 0 ;
  LOOP
    IF len = room
    THEN
      (* one more byte means the file is larger than the buffer *)
      n := read (fd, ADR (buf[len]), 1) ;
      IF n > 0 THEN err := EFBIG END ;
      EXIT
    END ;
    n := read (fd, ADR (buf[len]), room - len) ;
    IF n > 0
    THEN
      INC (len, n)
    ELSIF n = 0
    THEN
      EXIT
    ELSIF mx_errno () # EINTR
    THEN
      err := mx_errno () ;
      EXIT
    END
  END ;
  IF close (fd) # 0 THEN END ;
  IF err # 0
  THEN
    len := 0
  END ;
  buf[len] := 0C ;
  RETURN err
END Read ;

END TextFile.
