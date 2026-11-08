IMPLEMENTATION MODULE Config ;

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM libc IMPORT getenv ;
FROM Posix IMPORT ENOENT ;
IMPORT Str, Log, TextFile ;

CONST
  MaxEntries = 64 ;
  MaxFile = 65536 ;

TYPE
  Entry = RECORD
    key: ARRAY [0..31] OF CHAR ;
    value: ARRAY [0..255] OF CHAR ;
  END ;

VAR
  entries: ARRAY [0..MaxEntries - 1] OF Entry ;
  count: CARDINAL ;
  buffer: ARRAY [0..MaxFile] OF CHAR ;

PROCEDURE ConfigPath (name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR) : BOOLEAN ;
VAR
  p: ADDRESS ;
BEGIN
  p := getenv (ADR ("XDG_CONFIG_HOME")) ;
  IF (p # NIL) AND Str.FromC (p, path) AND (path[0] = '/')
  THEN
    RETURN Str.Append ("/", path) AND Str.Append (name, path)
  END ;
  p := getenv (ADR ("HOME")) ;
  RETURN (p # NIL) AND Str.FromC (p, path) AND
         Str.Append ("/.config/", path) AND Str.Append (name, path)
END ConfigPath ;

PROCEDURE LineError (VAR file: ARRAY OF CHAR; number: CARDINAL;
                     msg: ARRAY OF CHAR) ;
VAR
  where: ARRAY [0..4127] OF CHAR ;
  n: ARRAY [0..15] OF CHAR ;
BEGIN
  Str.IntToStr (number, n) ;
  IF Str.Assign (file, where) AND Str.Append (":", where) AND
     Str.Append (n, where)
  THEN
    Log.Error2 (where, msg)
  ELSE
    Log.Error2 (file, msg)
  END
END LineError ;

PROCEDURE ParseLine (VAR line: ARRAY OF CHAR; number: CARDINAL;
                     VAR file: ARRAY OF CHAR) ;
VAR
  i, eq: CARDINAL ;
  e: Entry ;
BEGIN
  Str.Trim (line) ;
  IF (line[0] = 0C) OR (line[0] = '#')
  THEN
    RETURN
  END ;
  eq := 0 ;
  WHILE (line[eq] # 0C) AND (line[eq] # '=') DO
    INC (eq)
  END ;
  IF line[eq] # '='
  THEN
    LineError (file, number, "missing '=', line ignored") ;
    RETURN
  END ;
  line[eq] := 0C ;
  IF (NOT Str.Assign (line, e.key)) OR (count = MaxEntries)
  THEN
    LineError (file, number, "key too long or too many keys, line ignored") ;
    RETURN
  END ;
  i := 0 ;
  WHILE line[eq + 1 + i] # 0C DO
    IF i >= HIGH (e.value)
    THEN
      LineError (file, number, "value too long, line ignored") ;
      RETURN
    END ;
    e.value[i] := line[eq + 1 + i] ;
    INC (i)
  END ;
  e.value[i] := 0C ;
  Str.Trim (e.key) ;
  Str.Trim (e.value) ;
  entries[count] := e ;
  INC (count)
END ParseLine ;

PROCEDURE Load ;
VAR
  path: ARRAY [0..4095] OF CHAR ;
  line: ARRAY [0..511] OF CHAR ;
  i, j, number, total: CARDINAL ;
  err: INTEGER ;
  overlong: BOOLEAN ;
BEGIN
  count := 0 ;
  IF NOT ConfigPath ("mosaic/mosaicrc", path)
  THEN
    RETURN
  END ;
  err := TextFile.Read (path, buffer, total) ;
  IF err = TextFile.EFBIG
  THEN
    Log.Error2 (path, "file too large, ignored") ;
    RETURN
  ELSIF err = ENOENT
  THEN
    RETURN
  ELSIF err # 0
  THEN
    Log.Error2 ("cannot read", path) ;
    RETURN
  END ;
  buffer[total] := 12C ;
  j := 0 ;
  number := 1 ;
  overlong := FALSE ;
  FOR i := 0 TO total DO
    IF buffer[i] = 12C
    THEN
      line[j] := 0C ;
      IF overlong
      THEN
        LineError (path, number, "line too long, ignored")
      ELSE
        ParseLine (line, number, path)
      END ;
      j := 0 ;
      overlong := FALSE ;
      INC (number)
    ELSIF j < HIGH (line)
    THEN
      line[j] := buffer[i] ;
      INC (j)
    ELSE
      overlong := TRUE
    END
  END
END Load ;

PROCEDURE Find (key: ARRAY OF CHAR) : INTEGER ;
VAR
  i: CARDINAL ;
BEGIN
  i := count ;
  (* later lines override earlier ones *)
  WHILE i > 0 DO
    DEC (i) ;
    IF Str.Equal (entries[i].key, key)
    THEN
      RETURN i
    END
  END ;
  RETURN -1
END Find ;

PROCEDURE Get (key, default: ARRAY OF CHAR; VAR value: ARRAY OF CHAR) ;
VAR
  i: INTEGER ;
BEGIN
  i := Find (key) ;
  IF (i < 0) OR NOT Str.Assign (entries[i].value, value)
  THEN
    IF NOT Str.Assign (default, value)
    THEN
      value[0] := 0C
    END
  END
END Get ;

PROCEDURE GetInt (key: ARRAY OF CHAR; default, min, max: INTEGER) : INTEGER ;
VAR
  i, v: INTEGER ;
BEGIN
  i := Find (key) ;
  IF i < 0
  THEN
    RETURN default
  END ;
  IF (NOT Str.StrToInt (entries[i].value, v)) OR (v < min) OR (v > max)
  THEN
    Log.Error2 ("invalid number in mosaicrc for", key) ;
    RETURN default
  END ;
  RETURN v
END GetInt ;

BEGIN
  count := 0
END Config.
