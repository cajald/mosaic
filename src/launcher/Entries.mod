IMPLEMENTATION MODULE Entries ;

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM libc IMPORT getenv ;
FROM Posix IMPORT ENOENT, ENOTDIR, SIFDIR, SIFREG, opendir, closedir,
                  mx_read_dir, mx_file_info, mx_errno ;
FROM Spawn IMPORT Args ;
IMPORT Str, Log, Spawn, TextFile ;

CONST
  MaxFile = 65535 ;
  MaxDepth = 4 ;
  Desktop = "Mosaic" ;

TYPE
  Text = POINTER TO ARRAY [0..255] OF CHAR ;

VAR
  buffer: ARRAY [0..MaxFile] OF CHAR ;
  seen: ARRAY [0..MaxEntries - 1] OF Text ;
  seenCount: CARDINAL ;
  langCountry, lang: ARRAY [0..31] OF CHAR ;
  mainCategories: ARRAY [1..Categories - 2] OF ARRAY [0..15] OF CHAR ;

(* "tr_TR.UTF-8@euro" gives tr_TR and tr *)
PROCEDURE ReadLocale ;
VAR
  p: ADDRESS ;
  value: ARRAY [0..63] OF CHAR ;
  i: CARDINAL ;
BEGIN
  langCountry[0] := 0C ;
  lang[0] := 0C ;
  p := getenv (ADR ("LC_ALL")) ;
  IF (p = NIL) OR NOT Str.FromC (p, value) OR (value[0] = 0C)
  THEN
    p := getenv (ADR ("LC_MESSAGES")) ;
    IF (p = NIL) OR NOT Str.FromC (p, value) OR (value[0] = 0C)
    THEN
      p := getenv (ADR ("LANG")) ;
      IF (p = NIL) OR NOT Str.FromC (p, value)
      THEN
        RETURN
      END
    END
  END ;
  i := 0 ;
  WHILE (value[i] # 0C) AND (value[i] # '.') AND (value[i] # '@') AND
        (i < HIGH (langCountry)) DO
    langCountry[i] := value[i] ;
    INC (i)
  END ;
  langCountry[i] := 0C ;
  i := 0 ;
  WHILE (langCountry[i] # 0C) AND (langCountry[i] # '_') DO
    lang[i] := langCountry[i] ;
    INC (i)
  END ;
  lang[i] := 0C
END ReadLocale ;

(* desktop entry string escapes: \s \n \t \r \\ *)
PROCEDURE Unescape (VAR s: ARRAY OF CHAR) ;
VAR
  i, j: CARDINAL ;
BEGIN
  i := 0 ;
  j := 0 ;
  WHILE s[i] # 0C DO
    IF (s[i] = '\') AND (s[i + 1] # 0C)
    THEN
      INC (i) ;
      CASE s[i] OF
        's': s[j] := ' ' |
        'n': s[j] := 12C |
        't': s[j] := 11C |
        'r': s[j] := 15C |
        '\': s[j] := '\'
      ELSE
        (* other escapes belong to the exec quoting rules *)
        s[j] := '\' ;
        INC (j) ;
        s[j] := s[i]
      END
    ELSE
      s[j] := s[i]
    END ;
    INC (i) ;
    INC (j)
  END ;
  s[j] := 0C
END Unescape ;

(* does the ;-separated list contain item *)
PROCEDURE ListHas (list, item: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i, start: CARDINAL ;
  part: ARRAY [0..63] OF CHAR ;
BEGIN
  i := 0 ;
  start := 0 ;
  LOOP
    IF (i > HIGH (list)) OR (list[i] = ';') OR (list[i] = 0C)
    THEN
      IF (i > start) AND (i - start <= HIGH (part))
      THEN
        Str.FromBytes (ADR (list[start]), i - start, part) ;
        IF Str.Equal (part, item)
        THEN
          RETURN TRUE
        END
      END ;
      IF (i > HIGH (list)) OR (list[i] = 0C)
      THEN
        RETURN FALSE
      END ;
      start := i + 1
    END ;
    INC (i)
  END
END ListHas ;

PROCEDURE CategoryOf (list: ARRAY OF CHAR) : CARDINAL ;
VAR
  i: CARDINAL ;
BEGIN
  IF ListHas (list, "Audio") OR ListHas (list, "Video")
  THEN
    RETURN 1
  END ;
  FOR i := 1 TO Categories - 2 DO
    IF ListHas (list, mainCategories[i])
    THEN
      RETURN i
    END
  END ;
  RETURN Categories - 1
END CategoryOf ;

(* rank of a key for the current locale: 0 no match, 1 plain, 2 lang,
   3 lang_COUNTRY *)
PROCEDURE LocaleRank (VAR key: ARRAY OF CHAR; base: ARRAY OF CHAR) : CARDINAL ;
VAR
  want: ARRAY [0..63] OF CHAR ;
BEGIN
  IF Str.Equal (key, base)
  THEN
    RETURN 1
  END ;
  IF (lang[0] # 0C) AND Str.Assign (base, want) AND Str.Append ("[", want) AND
     Str.Append (lang, want) AND Str.Append ("]", want) AND Str.Equal (key, want)
  THEN
    RETURN 2
  END ;
  IF (langCountry[0] # 0C) AND Str.Assign (base, want) AND
     Str.Append ("[", want) AND Str.Append (langCountry, want) AND
     Str.Append ("]", want) AND Str.Equal (key, want)
  THEN
    RETURN 3
  END ;
  RETURN 0
END LocaleRank ;

(* false if the file is not a launchable application *)
PROCEDURE Parse (path, id: ARRAY OF CHAR; VAR e: EntryRec) : BOOLEAN ;
VAR
  len, i, j, eq, nameRank, commentRank, rank: CARDINAL ;
  line: ARRAY [0..4095] OF CHAR ;
  key: ARRAY [0..63] OF CHAR ;
  value: ARRAY [0..4095] OF CHAR ;
  kind, categories, onlyShow, notShow, tryExec: ARRAY [0..1023] OF CHAR ;
  generic: ARRAY [0..255] OF CHAR ;
  inGroup, hidden, longLine, haveExec: BOOLEAN ;
BEGIN
  IF (TextFile.Read (path, buffer, len) # 0) OR
     NOT (Str.Assign (path, e.file) AND Str.Assign (id, e.id))
  THEN
    RETURN FALSE
  END ;
  e.name[0] := 0C ; e.comment[0] := 0C ; e.exec[0] := 0C ; e.dir[0] := 0C ;
  e.terminal := FALSE ;
  kind[0] := 0C ; categories[0] := 0C ; onlyShow[0] := 0C ;
  notShow[0] := 0C ; tryExec[0] := 0C ; generic[0] := 0C ;
  nameRank := 0 ; commentRank := 0 ;
  inGroup := FALSE ;
  hidden := FALSE ;
  haveExec := FALSE ;
  buffer[len] := 12C ;
  i := 0 ;
  WHILE i <= len DO
    (* cut out one line; lines that do not fit are skipped *)
    j := 0 ;
    longLine := FALSE ;
    WHILE buffer[i] # 12C DO
      IF j < HIGH (line) THEN line[j] := buffer[i] ; INC (j) ELSE longLine := TRUE END ;
      INC (i)
    END ;
    INC (i) ;
    line[j] := 0C ;
    IF (line[0] = '[') AND NOT longLine
    THEN
      inGroup := Str.Equal (line, "[Desktop Entry]")
    ELSIF inGroup AND (line[0] # '#') AND (line[0] # 0C) AND NOT longLine
    THEN
      eq := 0 ;
      WHILE (line[eq] # 0C) AND (line[eq] # '=') DO INC (eq) END ;
      IF (line[eq] = '=') AND (eq <= HIGH (key))
      THEN
        line[eq] := 0C ;
        IF NOT Str.Assign (line, key) THEN key[0] := 0C END ;
        j := eq + 1 ;
        WHILE line[j] # 0C DO INC (j) END ;
        Str.FromBytes (ADR (line[eq + 1]), j - eq - 1, value) ;
        Str.Trim (key) ;
        Str.Trim (value) ;
        Unescape (value) ;
        rank := LocaleRank (key, "Name") ;
        IF rank > nameRank
        THEN
          nameRank := rank ;
          Str.FromBytes (ADR (value), Str.Length (value), e.name)
        END ;
        rank := LocaleRank (key, "Comment") ;
        IF rank > commentRank
        THEN
          commentRank := rank ;
          Str.FromBytes (ADR (value), Str.Length (value), e.comment)
        END ;
        IF Str.Equal (key, "GenericName")
        THEN
          Str.FromBytes (ADR (value), Str.Length (value), generic)
        ELSIF Str.Equal (key, "Type")
        THEN
          IF Str.Assign (value, kind) THEN END
        ELSIF Str.Equal (key, "Exec")
        THEN
          haveExec := Str.Assign (value, e.exec)
        ELSIF Str.Equal (key, "Path")
        THEN
          IF NOT Str.Assign (value, e.dir) THEN hidden := TRUE END
        ELSIF Str.Equal (key, "TryExec")
        THEN
          IF NOT Str.Assign (value, tryExec) THEN hidden := TRUE END
        ELSIF Str.Equal (key, "Terminal")
        THEN
          e.terminal := Str.Equal (value, "true")
        ELSIF Str.Equal (key, "NoDisplay") OR Str.Equal (key, "Hidden")
        THEN
          IF Str.Equal (value, "true") THEN hidden := TRUE END
        ELSIF Str.Equal (key, "Categories")
        THEN
          IF Str.Assign (value, categories) THEN END
        ELSIF Str.Equal (key, "OnlyShowIn")
        THEN
          IF Str.Assign (value, onlyShow) THEN END
        ELSIF Str.Equal (key, "NotShowIn")
        THEN
          IF Str.Assign (value, notShow) THEN END
        END
      END
    END
  END ;
  IF e.comment[0] = 0C
  THEN
    e.comment := generic
  END ;
  e.category := CategoryOf (categories) ;
  RETURN (NOT hidden) AND haveExec AND (e.name[0] # 0C) AND
         Str.Equal (kind, "Application") AND
         ((onlyShow[0] = 0C) OR ListHas (onlyShow, Desktop)) AND
         NOT ListHas (notShow, Desktop) AND
         ((tryExec[0] = 0C) OR Spawn.Executable (tryExec))
END Parse ;

PROCEDURE AddArg (VAR a: Args; VAR cur: ARRAY OF CHAR; VAR used: BOOLEAN;
                  VAR reason: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  IF used
  THEN
    used := FALSE ;
    IF NOT Spawn.Add (a, cur)
    THEN
      IF Str.Assign ("the command line is too long", reason) THEN END ;
      RETURN FALSE
    END
  END ;
  cur[0] := 0C ;
  RETURN TRUE
END AddArg ;

PROCEDURE Command (VAR e: EntryRec; VAR a: Args;
                   VAR reason: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i: CARDINAL ;
  c: CHAR ;
  cur: ARRAY [0..4095] OF CHAR ;
  used, quoted, ok: BOOLEAN ;
  terminal: ARRAY [0..255] OF CHAR ;
BEGIN
  Spawn.Clear (a) ;
  IF e.terminal
  THEN
    IF NOT Spawn.Terminal (terminal)
    THEN
      IF Str.Assign ("it needs a terminal and none was found", reason) THEN END ;
      RETURN FALSE
    END ;
    IF NOT (Spawn.Add (a, terminal) AND Spawn.Add (a, "-e")) THEN RETURN FALSE END
  END ;
  cur[0] := 0C ;
  used := FALSE ;
  quoted := FALSE ;
  ok := TRUE ;
  i := 0 ;
  WHILE ok AND (e.exec[i] # 0C) DO
    c := e.exec[i] ;
    IF quoted
    THEN
      IF c = '"'
      THEN
        quoted := FALSE
      ELSIF (c = '\') AND ((e.exec[i + 1] = '"') OR (e.exec[i + 1] = '`') OR
                           (e.exec[i + 1] = '$') OR (e.exec[i + 1] = '\'))
      THEN
        INC (i) ;
        ok := Str.AppendChar (e.exec[i], cur)
      ELSE
        ok := Str.AppendChar (c, cur)
      END
    ELSIF (c = ' ') OR (c = 11C)
    THEN
      ok := AddArg (a, cur, used, reason)
    ELSIF c = '"'
    THEN
      quoted := TRUE ;
      used := TRUE
    ELSIF c = '%'
    THEN
      INC (i) ;
      CASE e.exec[i] OF
        '%': ok := Str.AppendChar ('%', cur) ; used := TRUE |
        'c': ok := Str.Append (e.name, cur) ; used := TRUE |
        'k': ok := Str.Append (e.file, cur) ; used := TRUE |
        'f', 'F', 'u', 'U', 'i', 'd', 'D', 'n', 'N', 'v', 'm':
          (* no files are passed from the launcher *)
      ELSE
        IF Str.Assign ("its Exec line has an invalid field code", reason) THEN END ;
        RETURN FALSE
      END
    ELSE
      ok := Str.AppendChar (c, cur) ;
      used := TRUE
    END ;
    INC (i)
  END ;
  IF quoted
  THEN
    IF Str.Assign ("its Exec line has an unterminated quote", reason) THEN END ;
    RETURN FALSE
  END ;
  IF NOT ok
  THEN
    IF Str.Assign ("its Exec line is too long", reason) THEN END ;
    RETURN FALSE
  END ;
  IF NOT AddArg (a, cur, used, reason)
  THEN
    RETURN FALSE
  END ;
  IF (a.count = 0) OR (e.terminal AND (a.count = 2))
  THEN
    IF Str.Assign ("its Exec line is empty", reason) THEN END ;
    RETURN FALSE
  END ;
  RETURN TRUE
END Command ;

PROCEDURE Seen (VAR id: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i: CARDINAL ;
  t: Text ;
BEGIN
  FOR i := 1 TO seenCount DO
    IF Str.Equal (seen[i - 1]^, id)
    THEN
      RETURN TRUE
    END
  END ;
  (* earlier directories win, so remember every id even if hidden *)
  IF seenCount < MaxEntries
  THEN
    NEW (t) ;
    IF Str.Assign (id, t^) THEN END ;
    seen[seenCount] := t ;
    INC (seenCount)
  END ;
  RETURN FALSE
END Seen ;

PROCEDURE Scan (dir, prefix: ARRAY OF CHAR; depth: CARDINAL) ;
VAR
  d, p: ADDRESS ;
  name: ARRAY [0..255] OF CHAR ;
  path: ARRAY [0..4095] OF CHAR ;
  id: ARRAY [0..255] OF CHAR ;
  mode: CARDINAL ;
  size, mtime: LONGINT ;
  e: EntryRec ;
  entry: Entry ;
BEGIN
  d := opendir (ADR (dir)) ;
  IF d = NIL
  THEN
    IF (mx_errno () # ENOENT) AND (mx_errno () # ENOTDIR)
    THEN
      Log.ErrorErrno ("cannot read", dir)
    END ;
    RETURN
  END ;
  LOOP
    p := mx_read_dir (d) ;
    IF p = NIL THEN EXIT END ;
    IF Str.FromC (p, name) AND (name[0] # '.') AND
       Str.Assign (dir, path) AND Str.Append ("/", path) AND
       Str.Append (name, path) AND
       (mx_file_info (ADR (path), 1, mode, size, mtime) = 0)
    THEN
      IF (mode DIV 4096 = SIFDIR DIV 4096) AND (depth < MaxDepth)
      THEN
        (* subdirectories become part of the id: kde/app.desktop -> kde-app *)
        IF Str.Assign (prefix, id) AND Str.Append (name, id) AND
           Str.Append ("-", id)
        THEN
          Scan (path, id, depth + 1)
        END
      ELSIF (mode DIV 4096 = SIFREG DIV 4096) AND
            Str.EndsWith (name, ".desktop") AND
            Str.Assign (prefix, id) AND Str.Append (name, id) AND
            NOT Seen (id) AND (count < MaxEntries) AND Parse (path, id, e)
      THEN
        NEW (entry) ;
        entry^ := e ;
        entries[count] := entry ;
        INC (count)
      END
    END
  END ;
  IF closedir (d) # 0 THEN END
END Scan ;

PROCEDURE ScanData (base: ARRAY OF CHAR) ;
VAR
  dir: ARRAY [0..4095] OF CHAR ;
BEGIN
  IF (base[0] = '/') AND Str.Assign (base, dir) AND
     Str.Append ("/applications", dir)
  THEN
    Scan (dir, "", 0)
  END
END ScanData ;

PROCEDURE Sort ;
VAR
  i, j: CARDINAL ;
  e: Entry ;
BEGIN
  FOR i := 1 TO count - 1 DO
    e := entries[i] ;
    j := i ;
    WHILE (j > 0) AND (Str.Compare (entries[j - 1]^.name, e^.name) > 0) DO
      entries[j] := entries[j - 1] ;
      DEC (j)
    END ;
    entries[j] := e
  END
END Sort ;

PROCEDURE Load ;
VAR
  p: ADDRESS ;
  dirs: ARRAY [0..4095] OF CHAR ;
  home: ARRAY [0..4095] OF CHAR ;
  i, start: CARDINAL ;
  last: BOOLEAN ;
BEGIN
  ReadLocale ;
  count := 0 ;
  seenCount := 0 ;
  p := getenv (ADR ("XDG_DATA_HOME")) ;
  IF (p # NIL) AND Str.FromC (p, home) AND (home[0] = '/')
  THEN
    ScanData (home)
  ELSE
    p := getenv (ADR ("HOME")) ;
    IF (p # NIL) AND Str.FromC (p, home) AND Str.Append ("/.local/share", home)
    THEN
      ScanData (home)
    END
  END ;
  p := getenv (ADR ("XDG_DATA_DIRS")) ;
  IF (p = NIL) OR NOT Str.FromC (p, dirs) OR (dirs[0] = 0C)
  THEN
    dirs := "/usr/local/share:/usr/share"
  END ;
  i := 0 ;
  start := 0 ;
  LOOP
    IF (dirs[i] = ':') OR (dirs[i] = 0C)
    THEN
      last := dirs[i] = 0C ;
      dirs[i] := 0C ;
      IF Str.FromC (ADR (dirs[start]), home)
      THEN
        ScanData (home)
      END ;
      IF last THEN EXIT END ;
      start := i + 1
    END ;
    INC (i)
  END ;
  IF count > 1
  THEN
    Sort
  END
END Load ;

BEGIN
  count := 0 ;
  seenCount := 0 ;
  categoryNames[0] := "All" ;
  categoryNames[1] := "Multimedia" ;
  categoryNames[2] := "Development" ;
  categoryNames[3] := "Education" ;
  categoryNames[4] := "Games" ;
  categoryNames[5] := "Graphics" ;
  categoryNames[6] := "Internet" ;
  categoryNames[7] := "Office" ;
  categoryNames[8] := "Science" ;
  categoryNames[9] := "Settings" ;
  categoryNames[10] := "System" ;
  categoryNames[11] := "Accessories" ;
  categoryNames[12] := "Other" ;
  mainCategories[1] := "AudioVideo" ;
  mainCategories[2] := "Development" ;
  mainCategories[3] := "Education" ;
  mainCategories[4] := "Game" ;
  mainCategories[5] := "Graphics" ;
  mainCategories[6] := "Network" ;
  mainCategories[7] := "Office" ;
  mainCategories[8] := "Science" ;
  mainCategories[9] := "Settings" ;
  mainCategories[10] := "System" ;
  mainCategories[11] := "Utility"
END Entries.
