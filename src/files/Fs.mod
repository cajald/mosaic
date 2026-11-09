IMPLEMENTATION MODULE Fs ;

FROM SYSTEM IMPORT ADR, ADDRESS, TSIZE ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM libc IMPORT open, close, read, write, memcpy ;
FROM Posix IMPORT EEXIST, ENOENT, EXDEV, EINVAL, ENOSYS, EINTR,
                  ATFDCWD, RENAMENOREPLACE, OREADONLY, OWRITEONLY, OCREAT,
                  OEXCL, OCLOEXEC, ONOFOLLOW, SIFDIR, SIFREG, SIFLNK,
                  mkdir, rmdir, unlink, renameat2, opendir, closedir,
                  symlink, readlink, chmod, mx_read_dir, mx_file_info,
                  mx_errno ;
IMPORT Str ;

CONST
  MaxDepth = 256 ;
  ChunkSize = 65536 ;
  MaxSuffix = 999 ;

TYPE
  PathPtr = POINTER TO Path ;
  Name = POINTER TO NameRec ;
  NameRec = RECORD
    text: ARRAY [0..NameMax - 1] OF CHAR ;
    next: Name ;
  END ;

VAR
  chunk: ARRAY [0..ChunkSize - 1] OF CHAR ;

PROCEDURE Fail (path: ARRAY OF CHAR; err: INTEGER) : INTEGER ;
BEGIN
  IF NOT Str.Assign (path, failedPath)
  THEN
    failedPath[0] := 0C
  END ;
  RETURN err
END Fail ;

PROCEDURE Kind (mode: CARDINAL) : CARDINAL ;
BEGIN
  RETURN mode DIV 4096
END Kind ;

PROCEDURE Init (VAR l: Listing) ;
BEGIN
  l.items := NIL ;
  l.count := 0 ;
  l.capacity := 0 ;
  l.skipped := 0
END Init ;

PROCEDURE Free (VAR l: Listing) ;
VAR
  i: CARDINAL ;
BEGIN
  FOR i := 1 TO l.count DO
    DISPOSE (l.items^[i - 1])
  END ;
  IF l.items # NIL
  THEN
    DEALLOCATE (l.items, l.capacity * TSIZE (Item))
  END ;
  Init (l)
END Free ;

PROCEDURE Append (VAR l: Listing; it: Item) ;
VAR
  bigger: ItemArray ;
  size: CARDINAL ;
BEGIN
  IF l.count = l.capacity
  THEN
    size := 2 * l.capacity ;
    IF size < 256 THEN size := 256 END ;
    ALLOCATE (bigger, size * TSIZE (Item)) ;
    IF l.items # NIL
    THEN
      IF memcpy (bigger, l.items, l.count * TSIZE (Item)) = NIL THEN END ;
      DEALLOCATE (l.items, l.capacity * TSIZE (Item))
    END ;
    l.items := bigger ;
    l.capacity := size
  END ;
  l.items^[l.count] := it ;
  INC (l.count)
END Append ;

PROCEDURE Before (a, b: Item) : BOOLEAN ;
BEGIN
  IF a^.isDir # b^.isDir
  THEN
    RETURN a^.isDir
  END ;
  RETURN Str.Compare (a^.name, b^.name) < 0
END Before ;

(* heapsort keeps huge folders fast without recursion *)
PROCEDURE SiftDown (VAR l: Listing; start, last: CARDINAL) ;
VAR
  root, child: CARDINAL ;
  t: Item ;
BEGIN
  root := start ;
  WHILE 2 * root + 1 <= last DO
    child := 2 * root + 1 ;
    IF (child + 1 <= last) AND Before (l.items^[child], l.items^[child + 1])
    THEN
      INC (child)
    END ;
    IF Before (l.items^[root], l.items^[child])
    THEN
      t := l.items^[root] ;
      l.items^[root] := l.items^[child] ;
      l.items^[child] := t ;
      root := child
    ELSE
      RETURN
    END
  END
END SiftDown ;

PROCEDURE Sort (VAR l: Listing) ;
VAR
  start, last: CARDINAL ;
  t: Item ;
BEGIN
  IF l.count < 2
  THEN
    RETURN
  END ;
  start := (l.count - 2) DIV 2 + 1 ;
  WHILE start > 0 DO
    DEC (start) ;
    SiftDown (l, start, l.count - 1)
  END ;
  last := l.count - 1 ;
  WHILE last > 0 DO
    t := l.items^[last] ;
    l.items^[last] := l.items^[0] ;
    l.items^[0] := t ;
    DEC (last) ;
    SiftDown (l, 0, last)
  END
END Sort ;

PROCEDURE Read (dir: ARRAY OF CHAR; showHidden: BOOLEAN;
                VAR l: Listing) : INTEGER ;
VAR
  d, p: ADDRESS ;
  it: Item ;
  path: PathPtr ;
  target: CARDINAL ;
  size, mtime: LONGINT ;
BEGIN
  Free (l) ;
  d := opendir (ADR (dir)) ;
  IF d = NIL
  THEN
    RETURN Fail (dir, mx_errno ())
  END ;
  NEW (path) ;
  LOOP
    p := mx_read_dir (d) ;
    IF p = NIL THEN EXIT END ;
    NEW (it) ;
    IF Str.FromC (p, it^.name) AND NOT Str.Equal (it^.name, ".") AND
       NOT Str.Equal (it^.name, "..") AND
       (showHidden OR (it^.name[0] # '.')) AND
       Join (dir, it^.name, path^) AND
       (mx_file_info (path, 0, it^.mode, it^.size, it^.mtime) = 0)
    THEN
      it^.isLink := Kind (it^.mode) = SIFLNK DIV 4096 ;
      it^.isDir := Kind (it^.mode) = SIFDIR DIV 4096 ;
      it^.broken := FALSE ;
      IF it^.isLink
      THEN
        (* a link shows what it points to *)
        IF mx_file_info (path, 1, target, size, mtime) = 0
        THEN
          it^.isDir := Kind (target) = SIFDIR DIV 4096 ;
          it^.size := size
        ELSE
          it^.broken := TRUE
        END
      END ;
      Append (l, it)
    ELSE
      IF NOT (Str.Equal (it^.name, ".") OR Str.Equal (it^.name, "..") OR
              (it^.name[0] = '.') AND NOT showHidden)
      THEN
        (* vanished while listing, or the full path is too long *)
        INC (l.skipped)
      END ;
      DISPOSE (it)
    END
  END ;
  DISPOSE (path) ;
  IF closedir (d) # 0 THEN END ;
  Sort (l) ;
  RETURN 0
END Read ;

PROCEDURE Join (dir, name: ARRAY OF CHAR; VAR out: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  IF NOT Str.Assign (dir, out)
  THEN
    RETURN FALSE
  END ;
  IF NOT Str.EndsWith (out, "/")
  THEN
    IF NOT Str.Append ("/", out) THEN RETURN FALSE END
  END ;
  RETURN Str.Append (name, out)
END Join ;

PROCEDURE Parent (VAR path: ARRAY OF CHAR) ;
VAR
  n: CARDINAL ;
BEGIN
  n := Str.Length (path) ;
  WHILE (n > 1) AND (path[n - 1] = '/') DO DEC (n) END ;
  WHILE (n > 0) AND (path[n - 1] # '/') DO DEC (n) END ;
  WHILE (n > 1) AND (path[n - 1] = '/') DO DEC (n) END ;
  IF n = 0
  THEN
    path[0] := '/' ;
    n := 1
  END ;
  path[n] := 0C
END Parent ;

PROCEDURE BaseName (path: ARRAY OF CHAR; VAR name: ARRAY OF CHAR) ;
VAR
  n, start: CARDINAL ;
BEGIN
  n := Str.Length (path) ;
  WHILE (n > 1) AND (path[n - 1] = '/') DO DEC (n) END ;
  start := n ;
  WHILE (start > 0) AND (path[start - 1] # '/') DO DEC (start) END ;
  Str.FromBytes (ADR (path[start]), n - start, name)
END BaseName ;

PROCEDURE ValidName (name: ARRAY OF CHAR) : BOOLEAN ;
VAR
  i, n: CARDINAL ;
BEGIN
  n := Str.Length (name) ;
  IF (n = 0) OR (n >= NameMax) OR Str.Equal (name, ".") OR
     Str.Equal (name, "..")
  THEN
    RETURN FALSE
  END ;
  FOR i := 0 TO n - 1 DO
    IF name[i] = '/' THEN RETURN FALSE END
  END ;
  RETURN TRUE
END ValidName ;

PROCEDURE Exists (path: ARRAY OF CHAR) : BOOLEAN ;
VAR
  mode: CARDINAL ;
  size, mtime: LONGINT ;
BEGIN
  RETURN mx_file_info (ADR (path), 0, mode, size, mtime) = 0
END Exists ;

PROCEDURE IsDirectory (path: ARRAY OF CHAR) : BOOLEAN ;
VAR
  mode: CARDINAL ;
  size, mtime: LONGINT ;
BEGIN
  RETURN (mx_file_info (ADR (path), 1, mode, size, mtime) = 0) AND
         (Kind (mode) = SIFDIR DIV 4096)
END IsDirectory ;

PROCEDURE MakeDir (path: ARRAY OF CHAR) : INTEGER ;
BEGIN
  IF mkdir (ADR (path), 511) # 0
  THEN
    RETURN Fail (path, mx_errno ())
  END ;
  RETURN 0
END MakeDir ;

PROCEDURE Rename (oldPath, newPath: ARRAY OF CHAR) : INTEGER ;
VAR
  err: INTEGER ;
BEGIN
  IF renameat2 (ATFDCWD, ADR (oldPath), ATFDCWD, ADR (newPath), RENAMENOREPLACE) = 0
  THEN
    RETURN 0
  END ;
  err := mx_errno () ;
  IF (err = EINVAL) OR (err = ENOSYS)
  THEN
    (* shortcut: filesystems without RENAME_NOREPLACE get a check then
       rename, racy against other writers; fine for one desktop user *)
    IF Exists (newPath)
    THEN
      RETURN Fail (newPath, EEXIST)
    END ;
    IF renameat2 (ATFDCWD, ADR (oldPath), ATFDCWD, ADR (newPath), 0) = 0
    THEN
      RETURN 0
    END ;
    err := mx_errno ()
  END ;
  RETURN Fail (oldPath, err)
END Rename ;

(* destDir/name, or destDir/stem (n).ext for the first free n *)
PROCEDURE FreeName (src, destDir: ARRAY OF CHAR;
                    VAR out: ARRAY OF CHAR) : INTEGER ;
VAR
  name, stem, ext, candidate: ARRAY [0..NameMax + 15] OF CHAR ;
  number: ARRAY [0..7] OF CHAR ;
  i, dot: CARDINAL ;
  n: INTEGER ;
BEGIN
  BaseName (src, name) ;
  IF NOT Join (destDir, name, out)
  THEN
    RETURN Fail (destDir, ENOENT)
  END ;
  IF NOT Exists (out)
  THEN
    RETURN 0
  END ;
  dot := 0 ;
  FOR i := 1 TO Str.Length (name) DO
    IF name[i - 1] = '.' THEN dot := i - 1 END
  END ;
  IF dot = 0
  THEN
    dot := Str.Length (name)
  END ;
  Str.FromBytes (ADR (name), dot, stem) ;
  IF NOT Str.FromC (ADR (name[dot]), ext) THEN ext[0] := 0C END ;
  FOR n := 2 TO MaxSuffix DO
    Str.IntToStr (n, number) ;
    IF Str.Assign (stem, candidate) AND Str.Append (" (", candidate) AND
       Str.Append (number, candidate) AND Str.Append (")", candidate) AND
       Str.Append (ext, candidate) AND ValidName (candidate) AND
       Join (destDir, candidate, out) AND NOT Exists (out)
    THEN
      RETURN 0
    END
  END ;
  RETURN Fail (out, EEXIST)
END FreeName ;

PROCEDURE WriteAll (fd: INTEGER; n: INTEGER) : INTEGER ;
VAR
  done, w: INTEGER ;
BEGIN
  done := 0 ;
  WHILE done < n DO
    w := write (fd, ADR (chunk[done]), n - done) ;
    IF w > 0
    THEN
      INC (done, w)
    ELSIF mx_errno () # EINTR
    THEN
      RETURN mx_errno ()
    END
  END ;
  RETURN 0
END WriteAll ;

PROCEDURE CopyFile (src, dst: ARRAY OF CHAR; mode: CARDINAL) : INTEGER ;
VAR
  inFd, outFd, n, err: INTEGER ;
BEGIN
  inFd := open (ADR (src), OREADONLY + OCLOEXEC + ONOFOLLOW, 0) ;
  IF inFd < 0
  THEN
    RETURN Fail (src, mx_errno ())
  END ;
  (* O_EXCL: an existing file is never truncated *)
  outFd := open (ADR (dst), OWRITEONLY + OCREAT + OEXCL + OCLOEXEC,
               mode MOD 512) ;
  IF outFd < 0
  THEN
    err := mx_errno () ;
    IF close (inFd) # 0 THEN END ;
    RETURN Fail (dst, err)
  END ;
  err := 0 ;
  LOOP
    n := read (inFd, ADR (chunk), ChunkSize) ;
    IF n = 0
    THEN
      EXIT
    ELSIF n < 0
    THEN
      IF mx_errno () # EINTR
      THEN
        err := Fail (src, mx_errno ()) ;
        EXIT
      END
    ELSE
      err := WriteAll (outFd, n) ;
      IF err # 0
      THEN
        err := Fail (dst, err) ;
        EXIT
      END
    END
  END ;
  IF close (inFd) # 0 THEN END ;
  IF (close (outFd) # 0) AND (err = 0)
  THEN
    err := Fail (dst, mx_errno ())
  END ;
  IF err # 0
  THEN
    (* the partial copy is ours, created with O_EXCL above *)
    IF unlink (ADR (dst)) # 0 THEN END
  END ;
  RETURN err
END CopyFile ;

PROCEDURE CopyLink (src, dst: ARRAY OF CHAR) : INTEGER ;
VAR
  target: PathPtr ;
  n: LONGINT ;
  err: INTEGER ;
BEGIN
  NEW (target) ;
  n := readlink (ADR (src), target, PathMax - 1) ;
  err := 0 ;
  IF n < 0
  THEN
    err := Fail (src, mx_errno ())
  ELSE
    target^[VAL (CARDINAL, n)] := 0C ;
    IF symlink (target, ADR (dst)) # 0
    THEN
      err := Fail (dst, mx_errno ())
    END
  END ;
  DISPOSE (target) ;
  RETURN err
END CopyLink ;

(* names in a folder, read before recursing so no handle stays open *)
PROCEDURE Names (dir: ARRAY OF CHAR; VAR list: Name) : INTEGER ;
VAR
  d, p: ADDRESS ;
  n: Name ;
BEGIN
  list := NIL ;
  d := opendir (ADR (dir)) ;
  IF d = NIL
  THEN
    RETURN Fail (dir, mx_errno ())
  END ;
  LOOP
    p := mx_read_dir (d) ;
    IF p = NIL THEN EXIT END ;
    NEW (n) ;
    IF Str.FromC (p, n^.text) AND NOT Str.Equal (n^.text, ".") AND
       NOT Str.Equal (n^.text, "..")
    THEN
      n^.next := list ;
      list := n
    ELSE
      DISPOSE (n)
    END
  END ;
  IF closedir (d) # 0 THEN END ;
  RETURN 0
END Names ;

PROCEDURE FreeNames (VAR list: Name) ;
VAR
  n: Name ;
BEGIN
  WHILE list # NIL DO
    n := list ;
    list := list^.next ;
    DISPOSE (n)
  END
END FreeNames ;

PROCEDURE CopyTree (src, dst: ARRAY OF CHAR; depth: CARDINAL) : INTEGER ;
VAR
  mode: CARDINAL ;
  size, mtime: LONGINT ;
  list, n: Name ;
  source, dest: PathPtr ;
  err: INTEGER ;
BEGIN
  IF depth > MaxDepth
  THEN
    RETURN Fail (src, ETooDeep)
  END ;
  IF mx_file_info (ADR (src), 0, mode, size, mtime) # 0
  THEN
    RETURN Fail (src, mx_errno ())
  END ;
  IF Kind (mode) = SIFLNK DIV 4096
  THEN
    RETURN CopyLink (src, dst)
  ELSIF Kind (mode) = SIFREG DIV 4096
  THEN
    RETURN CopyFile (src, dst, mode)
  ELSIF Kind (mode) # SIFDIR DIV 4096
  THEN
    (* devices, sockets and pipes are not copied *)
    RETURN Fail (src, EINVAL)
  END ;
  (* owner-only while filling, real mode once complete *)
  IF mkdir (ADR (dst), 448) # 0
  THEN
    RETURN Fail (dst, mx_errno ())
  END ;
  err := Names (src, list) ;
  NEW (source) ;
  NEW (dest) ;
  n := list ;
  WHILE (err = 0) AND (n # NIL) DO
    IF Join (src, n^.text, source^) AND Join (dst, n^.text, dest^)
    THEN
      err := CopyTree (source^, dest^, depth + 1)
    ELSE
      err := Fail (src, ETooDeep)
    END ;
    n := n^.next
  END ;
  DISPOSE (source) ;
  DISPOSE (dest) ;
  FreeNames (list) ;
  IF chmod (ADR (dst), mode MOD 4096) # 0 THEN END ;
  RETURN err
END CopyTree ;

(* copying or moving a folder into itself would never end *)
PROCEDURE Inside (src, destDir: ARRAY OF CHAR) : BOOLEAN ;
VAR
  prefix: Path ;
BEGIN
  RETURN Str.Equal (src, destDir) OR
         (Str.Assign (src, prefix) AND Str.Append ("/", prefix) AND
          Str.StartsWith (destDir, prefix))
END Inside ;

PROCEDURE Copy (src, destDir: ARRAY OF CHAR;
                VAR created: ARRAY OF CHAR) : INTEGER ;
VAR
  err: INTEGER ;
  failed: Path ;
BEGIN
  IF Inside (src, destDir)
  THEN
    RETURN Fail (src, EIntoItself)
  END ;
  err := FreeName (src, destDir, created) ;
  IF err = 0
  THEN
    err := CopyTree (src, created, 0) ;
    IF (err # 0) AND Exists (created)
    THEN
      (* leave nothing half copied behind *)
      failed := failedPath ;
      IF Delete (created) # 0 THEN END ;
      err := Fail (failed, err)
    END
  END ;
  RETURN err
END Copy ;

PROCEDURE Move (src, destDir: ARRAY OF CHAR;
                VAR created: ARRAY OF CHAR) : INTEGER ;
VAR
  err: INTEGER ;
  failed, parent: Path ;
BEGIN
  IF Inside (src, destDir)
  THEN
    RETURN Fail (src, EIntoItself)
  END ;
  IF Str.Assign (src, parent)
  THEN
    Parent (parent) ;
    IF Str.Equal (parent, destDir) AND Str.Assign (src, created)
    THEN
      (* already there *)
      RETURN 0
    END
  END ;
  err := FreeName (src, destDir, created) ;
  IF err # 0
  THEN
    RETURN err
  END ;
  err := Rename (src, created) ;
  IF err = EXDEV
  THEN
    (* across filesystems: copy, and remove the source only once the
       copy is complete *)
    err := CopyTree (src, created, 0) ;
    IF err = 0
    THEN
      err := Delete (src)
    ELSE
      failed := failedPath ;
      IF Exists (created) AND (Delete (created) # 0) THEN END ;
      err := Fail (failed, err)
    END
  END ;
  RETURN err
END Move ;

PROCEDURE DeleteTree (path: ARRAY OF CHAR; depth: CARDINAL) : INTEGER ;
VAR
  mode: CARDINAL ;
  size, mtime: LONGINT ;
  list, n: Name ;
  child: PathPtr ;
  err: INTEGER ;
BEGIN
  IF depth > MaxDepth
  THEN
    RETURN Fail (path, ETooDeep)
  END ;
  IF mx_file_info (ADR (path), 0, mode, size, mtime) # 0
  THEN
    RETURN Fail (path, mx_errno ())
  END ;
  IF Kind (mode) # SIFDIR DIV 4096
  THEN
    IF unlink (ADR (path)) # 0
    THEN
      RETURN Fail (path, mx_errno ())
    END ;
    RETURN 0
  END ;
  err := Names (path, list) ;
  NEW (child) ;
  n := list ;
  WHILE (err = 0) AND (n # NIL) DO
    IF Join (path, n^.text, child^)
    THEN
      err := DeleteTree (child^, depth + 1)
    ELSE
      err := Fail (path, ETooDeep)
    END ;
    n := n^.next
  END ;
  DISPOSE (child) ;
  FreeNames (list) ;
  IF err # 0
  THEN
    RETURN err
  END ;
  IF rmdir (ADR (path)) # 0
  THEN
    RETURN Fail (path, mx_errno ())
  END ;
  RETURN 0
END DeleteTree ;

PROCEDURE Delete (path: ARRAY OF CHAR) : INTEGER ;
BEGIN
  RETURN DeleteTree (path, 0)
END Delete ;

BEGIN
  failedPath[0] := 0C
END Fs.
