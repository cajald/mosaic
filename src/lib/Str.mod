IMPLEMENTATION MODULE Str ;

FROM SYSTEM IMPORT ADDRESS ;

TYPE
  Bytes = POINTER TO ARRAY [0..MAX (INTEGER) - 1] OF CHAR ;

PROCEDURE Length (s: ARRAY OF CHAR) : CARDINAL ;
VAR
  i: CARDINAL ;
BEGIN
  i := 0 ;
  WHILE (i <= HIGH (s)) AND (s[i] # 0C) DO
    INC (i)
  END ;
  RETURN i
END Length ;

PROCEDURE Equal (a, b: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  RETURN Compare0 (a, b, FALSE) = 0
END Equal ;

PROCEDURE Assign (src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  dst[0] := 0C ;
  RETURN Append (src, dst)
END Assign ;

PROCEDURE Append (src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i, j, n: CARDINAL ;
BEGIN
  i := Length (dst) ;
  n := Length (src) ;
  IF i + n > HIGH (dst)
  THEN
    RETURN FALSE
  END ;
  j := 0 ;
  WHILE j < n DO
    dst[i + j] := src[j] ;
    INC (j)
  END ;
  dst[i + n] := 0C ;
  RETURN TRUE
END Append ;

PROCEDURE AppendChar (c: CHAR; VAR dst: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i: CARDINAL ;
BEGIN
  i := Length (dst) ;
  IF i + 1 > HIGH (dst)
  THEN
    RETURN FALSE
  END ;
  dst[i] := c ;
  dst[i + 1] := 0C ;
  RETURN TRUE
END AppendChar ;

PROCEDURE FromC (p: ADDRESS; VAR dst: ARRAY OF CHAR) : BOOLEAN ;
VAR
  b: Bytes ;
  i: CARDINAL ;
BEGIN
  b := p ;
  i := 0 ;
  WHILE b^[i] # 0C DO
    IF i >= HIGH (dst)
    THEN
      dst[0] := 0C ;
      RETURN FALSE
    END ;
    dst[i] := b^[i] ;
    INC (i)
  END ;
  dst[i] := 0C ;
  RETURN TRUE
END FromC ;

PROCEDURE FromBytes (p: ADDRESS; n: CARDINAL; VAR dst: ARRAY OF CHAR) ;
VAR
  b: Bytes ;
  i: CARDINAL ;
BEGIN
  b := p ;
  i := 0 ;
  WHILE (i < n) AND (i < HIGH (dst)) AND (b^[i] # 0C) DO
    dst[i] := b^[i] ;
    INC (i)
  END ;
  dst[i] := 0C ;
  IF i < n
  THEN
    Shorten (dst, i)
  END
END FromBytes ;

(* cut to at most n bytes without splitting a utf-8 sequence *)
PROCEDURE Shorten (VAR s: ARRAY OF CHAR; n: CARDINAL) ;
BEGIN
  IF n >= Length (s)
  THEN
    RETURN
  END ;
  WHILE (n > 0) AND (ORD (s[n]) DIV 64 = 2) DO
    DEC (n)
  END ;
  s[n] := 0C
END Shorten ;

PROCEDURE StartsWith (s, prefix: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i, n: CARDINAL ;
BEGIN
  n := Length (prefix) ;
  IF n > Length (s)
  THEN
    RETURN FALSE
  END ;
  i := 0 ;
  WHILE i < n DO
    IF s[i] # prefix[i]
    THEN
      RETURN FALSE
    END ;
    INC (i)
  END ;
  RETURN TRUE
END StartsWith ;

PROCEDURE EndsWith (s, suffix: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i, n, m: CARDINAL ;
BEGIN
  n := Length (suffix) ;
  m := Length (s) ;
  IF n > m
  THEN
    RETURN FALSE
  END ;
  FOR i := 1 TO n DO
    IF s[m - i] # suffix[n - i]
    THEN
      RETURN FALSE
    END
  END ;
  RETURN TRUE
END EndsWith ;

PROCEDURE Lower (c: CHAR) : CHAR ;
BEGIN
  IF (c >= 'A') AND (c <= 'Z')
  THEN
    RETURN CHR (ORD (c) + 32)
  END ;
  RETURN c
END Lower ;

PROCEDURE Compare0 (a, b: ARRAY OF CHAR; fold: BOOLEAN) : INTEGER ;
VAR
  i: CARDINAL ;
  ca, cb: CHAR ;
BEGIN
  i := 0 ;
  LOOP
    IF i <= HIGH (a) THEN ca := a[i] ELSE ca := 0C END ;
    IF i <= HIGH (b) THEN cb := b[i] ELSE cb := 0C END ;
    IF fold
    THEN
      ca := Lower (ca) ;
      cb := Lower (cb)
    END ;
    IF ca # cb
    THEN
      RETURN VAL (INTEGER, ORD (ca)) - VAL (INTEGER, ORD (cb))
    END ;
    IF ca = 0C
    THEN
      RETURN 0
    END ;
    INC (i)
  END
END Compare0 ;

PROCEDURE Compare (a, b: ARRAY OF CHAR) : INTEGER ;
VAR
  r: INTEGER ;
BEGIN
  r := Compare0 (a, b, TRUE) ;
  IF r = 0
  THEN
    r := Compare0 (a, b, FALSE)
  END ;
  RETURN r
END Compare ;

PROCEDURE ContainsNoCase (s, part: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i, j, n, m: CARDINAL ;
BEGIN
  n := Length (s) ;
  m := Length (part) ;
  IF m = 0
  THEN
    RETURN TRUE
  END ;
  i := 0 ;
  WHILE i + m <= n DO
    j := 0 ;
    WHILE (j < m) AND (Lower (s[i + j]) = Lower (part[j])) DO
      INC (j)
    END ;
    IF j = m
    THEN
      RETURN TRUE
    END ;
    INC (i)
  END ;
  RETURN FALSE
END ContainsNoCase ;

PROCEDURE IntToStr (n: LONGINT; VAR s: ARRAY OF CHAR) ;
VAR
  digits: ARRAY [0..23] OF CHAR ;
  i, j: CARDINAL ;
  neg: BOOLEAN ;
  u: LONGCARD ;
BEGIN
  neg := n < 0 ;
  IF neg
  THEN
    u := VAL (LONGCARD, -(n + 1)) + 1
  ELSE
    u := VAL (LONGCARD, n)
  END ;
  i := 0 ;
  REPEAT
    digits[i] := CHR (ORD ('0') + VAL (CARDINAL, u MOD 10)) ;
    u := u DIV 10 ;
    INC (i)
  UNTIL u = 0 ;
  IF neg
  THEN
    digits[i] := '-' ;
    INC (i)
  END ;
  j := 0 ;
  WHILE (i > 0) AND (j < HIGH (s)) DO
    DEC (i) ;
    s[j] := digits[i] ;
    INC (j)
  END ;
  s[j] := 0C
END IntToStr ;

PROCEDURE StrToInt (s: ARRAY OF CHAR; VAR n: INTEGER) : BOOLEAN ;
VAR
  i: CARDINAL ;
  neg: BOOLEAN ;
  v: LONGINT ;
BEGIN
  i := 0 ;
  neg := FALSE ;
  IF (HIGH (s) > 0) AND (s[0] = '-')
  THEN
    neg := TRUE ;
    INC (i)
  END ;
  IF (i > HIGH (s)) OR (s[i] < '0') OR (s[i] > '9')
  THEN
    RETURN FALSE
  END ;
  v := 0 ;
  WHILE (i <= HIGH (s)) AND (s[i] >= '0') AND (s[i] <= '9') DO
    v := v * 10 + VAL (LONGINT, ORD (s[i]) - ORD ('0')) ;
    IF v > VAL (LONGINT, MAX (INTEGER))
    THEN
      RETURN FALSE
    END ;
    INC (i)
  END ;
  IF (i <= HIGH (s)) AND (s[i] # 0C)
  THEN
    RETURN FALSE
  END ;
  IF neg
  THEN
    v := -v
  END ;
  n := VAL (INTEGER, v) ;
  RETURN TRUE
END StrToInt ;

PROCEDURE Trim (VAR s: ARRAY OF CHAR) ;
VAR
  i, j, n: CARDINAL ;
BEGIN
  n := Length (s) ;
  WHILE (n > 0) AND (s[n - 1] <= ' ') DO
    DEC (n)
  END ;
  i := 0 ;
  WHILE (i < n) AND (s[i] <= ' ') DO
    INC (i)
  END ;
  j := 0 ;
  WHILE i < n DO
    s[j] := s[i] ;
    INC (i) ;
    INC (j)
  END ;
  IF j <= HIGH (s)
  THEN
    s[j] := 0C
  END
END Trim ;

END Str.
