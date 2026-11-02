IMPLEMENTATION MODULE Log ;

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM libc IMPORT write, strlen ;
FROM StrLib IMPORT StrLen, StrCopy ;
FROM errno IMPORT geterrno ;
FROM Posix IMPORT strerror ;

TYPE
  CharPtr = POINTER TO CHAR ;

VAR
  program: ARRAY [0..31] OF CHAR ;

PROCEDURE SetProgram (name: ARRAY OF CHAR) ;
BEGIN
  StrCopy (name, program)
END SetProgram ;

PROCEDURE Put (fd: INTEGER; s: ARRAY OF CHAR) ;
BEGIN
  IF StrLen (s) > 0
  THEN
    write (fd, ADR (s), StrLen (s))
  END
END Put ;

PROCEDURE Out (s: ARRAY OF CHAR) ;
BEGIN
  Put (1, s)
END Out ;

PROCEDURE OutLn (s: ARRAY OF CHAR) ;
BEGIN
  Put (1, s) ; Put (1, 12C)
END OutLn ;

PROCEDURE Error (s: ARRAY OF CHAR) ;
BEGIN
  Put (2, program) ; Put (2, ": ") ; Put (2, s) ; Put (2, 12C)
END Error ;

PROCEDURE Error2 (s, detail: ARRAY OF CHAR) ;
BEGIN
  Put (2, program) ; Put (2, ": ") ; Put (2, s) ; Put (2, ": ") ;
  Put (2, detail) ; Put (2, 12C)
END Error2 ;

PROCEDURE ErrorErrno (s, detail: ARRAY OF CHAR) ;
VAR
  msg: ADDRESS ;
BEGIN
  msg := strerror (geterrno ()) ;
  Put (2, program) ; Put (2, ": ") ; Put (2, s) ;
  IF StrLen (detail) > 0
  THEN
    Put (2, " '") ; Put (2, detail) ; Put (2, "'")
  END ;
  Put (2, ": ") ;
  write (2, msg, strlen (msg)) ;
  Put (2, 12C)
END ErrorErrno ;

BEGIN
  program := "mosaic"
END Log.
