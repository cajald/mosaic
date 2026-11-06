IMPLEMENTATION MODULE Spawn ;

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM libc IMPORT getenv ;
FROM Posix IMPORT XOK, WNOHANG, access, waitpid, readlink, mx_spawn ;
IMPORT Str, Log, Config ;

PROCEDURE Clear (VAR a: Args) ;
BEGIN
  a.count := 0 ;
  a.used := 0 ;
  a.overflow := FALSE
END Clear ;

PROCEDURE Add (VAR a: Args; arg: ARRAY OF CHAR) : BOOLEAN ;
VAR
  n, i: CARDINAL ;
BEGIN
  n := Str.Length (arg) ;
  IF a.overflow OR (a.count = MaxArgs - 1) OR (a.used + n + 1 > HIGH (a.data))
  THEN
    a.overflow := TRUE ;
    RETURN FALSE
  END ;
  a.offsets[a.count] := a.used ;
  i := 0 ;
  WHILE i < n DO
    a.data[a.used + i] := arg[i] ;
    INC (i)
  END ;
  a.data[a.used + n] := 0C ;
  INC (a.used, n + 1) ;
  INC (a.count) ;
  RETURN TRUE
END Add ;

PROCEDURE Get (VAR a: Args; i: CARDINAL; VAR arg: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  RETURN (i < a.count) AND Str.FromC (ADR (a.data[a.offsets[i]]), arg)
END Get ;

PROCEDURE Run (VAR a: Args; dir: ARRAY OF CHAR) : INTEGER ;
VAR
  argv: ARRAY [0..MaxArgs - 1] OF ADDRESS ;
  i: CARDINAL ;
  pid: INTEGER ;
  name: ARRAY [0..255] OF CHAR ;
BEGIN
  IF a.overflow OR (a.count = 0)
  THEN
    Log.Error ("command line too long, not started") ;
    RETURN -1
  END ;
  IF Get (a, 0, name) AND NOT Executable (name)
  THEN
    Log.Error2 ("program not found", name) ;
    RETURN -1
  END ;
  FOR i := 0 TO a.count - 1 DO
    argv[i] := ADR (a.data[a.offsets[i]])
  END ;
  argv[a.count] := NIL ;
  IF dir[0] = 0C
  THEN
    pid := mx_spawn (ADR (argv), NIL)
  ELSE
    pid := mx_spawn (ADR (argv), ADR (dir))
  END ;
  IF pid < 0
  THEN
    Log.ErrorErrno ("cannot start", name)
  END ;
  RETURN pid
END Run ;

PROCEDURE Executable (name: ARRAY OF CHAR) : BOOLEAN ;
VAR
  path: ARRAY [0..4095] OF CHAR ;
  dirs: ARRAY [0..4095] OF CHAR ;
  p: ADDRESS ;
  i, start: CARDINAL ;
  last: BOOLEAN ;
BEGIN
  IF name[0] = 0C
  THEN
    RETURN FALSE
  END ;
  i := 0 ;
  WHILE (i <= HIGH (name)) AND (name[i] # 0C) DO
    IF name[i] = '/'
    THEN
      RETURN access (ADR (name), XOK) = 0
    END ;
    INC (i)
  END ;
  p := getenv (ADR ("PATH")) ;
  IF (p = NIL) OR NOT Str.FromC (p, dirs)
  THEN
    dirs := "/usr/local/bin:/usr/bin:/bin"
  END ;
  start := 0 ;
  i := 0 ;
  LOOP
    IF (dirs[i] = ':') OR (dirs[i] = 0C)
    THEN
      last := dirs[i] = 0C ;
      dirs[i] := 0C ;
      IF (i > start) AND Str.FromC (ADR (dirs[start]), path) AND
         Str.Append ("/", path) AND Str.Append (name, path) AND
         (access (ADR (path), XOK) = 0)
      THEN
        RETURN TRUE
      END ;
      IF last
      THEN
        EXIT
      END ;
      start := i + 1
    END ;
    INC (i)
  END ;
  RETURN FALSE
END Executable ;

PROCEDURE Sibling (name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR) ;
VAR
  self: ARRAY [0..4095] OF CHAR ;
  n: LONGINT ;
  i: CARDINAL ;
BEGIN
  n := readlink (ADR ("/proc/self/exe"), ADR (self), HIGH (self)) ;
  IF n > 0
  THEN
    self[VAL (CARDINAL, n)] := 0C ;
    i := VAL (CARDINAL, n) ;
    WHILE (i > 0) AND (self[i - 1] # '/') DO
      DEC (i)
    END ;
    self[i] := 0C ;
    IF Str.Append (name, self) AND (access (ADR (self), XOK) = 0) AND
       Str.Assign (self, path)
    THEN
      RETURN
    END
  END ;
  IF NOT Str.Assign (name, path)
  THEN
    path[0] := 0C
  END
END Sibling ;

PROCEDURE Terminal (VAR name: ARRAY OF CHAR) : BOOLEAN ;
CONST
  Count = 9 ;
VAR
  known: ARRAY [0..Count - 1] OF ARRAY [0..15] OF CHAR ;
  i: CARDINAL ;
BEGIN
  Config.Get ("terminal", "", name) ;
  IF name[0] # 0C
  THEN
    RETURN Executable (name)
  END ;
  known[0] := "xterm" ;
  known[1] := "urxvt" ;
  known[2] := "st" ;
  known[3] := "alacritty" ;
  known[4] := "kitty" ;
  known[5] := "konsole" ;
  known[6] := "xfce4-terminal" ;
  known[7] := "gnome-terminal" ;
  known[8] := "lxterminal" ;
  FOR i := 0 TO Count - 1 DO
    IF Executable (known[i]) AND Str.Assign (known[i], name)
    THEN
      RETURN TRUE
    END
  END ;
  RETURN FALSE
END Terminal ;

PROCEDURE Reap () : INTEGER ;
VAR
  status, pid: INTEGER ;
BEGIN
  pid := waitpid (-1, status, WNOHANG) ;
  IF pid > 0
  THEN
    RETURN pid
  END ;
  RETURN 0
END Reap ;

END Spawn.
