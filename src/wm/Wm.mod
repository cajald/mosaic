IMPLEMENTATION MODULE Wm ;

FROM SYSTEM IMPORT ADDRESS, TSIZE ;
FROM Xlib IMPORT Window, Atom, Time, None, CurrentTime, False,
                 XSelectInput, XMapWindow, XUnmapWindow, XRestackWindows,
                 XSetInputFocus, XGrabButton, XUngrabButton, XAllowEvents,
                 XGetTransientForHint, XGetWMProtocols, XFree, XKillClient,
                 XQueryTree, XGrabServer, XUngrabServer, XSync,
                 XMoveResizeWindow,
                 MapRequest, UnmapNotify, DestroyNotify, ConfigureRequest,
                 PropertyNotify, ClientMessage, ButtonPress, Expose,
                 KeyPress, KeyRelease, ButtonRelease, MotionNotify,
                 SubstructureRedirectMask, SubstructureNotifyMask,
                 PropertyChangeMask, StructureNotifyMask, ButtonPressMask,
                 FocusChangeMask,
                 AnyButton, AnyModifier, GrabModeSync, GrabModeAsync,
                 ReplayPointer, RevertToPointerRoot, CWX, CWY, CWWidth,
                 CWHeight, CWStackMode, Above, IsViewable, NormalState,
                 IconicState, WithdrawnState, XA_ATOM, XA_CARDINAL,
                 XA_WM_NAME, XA_WM_HINTS, XA_WM_NORMAL_HINTS,
                 XA_WM_TRANSIENT_FOR ;
FROM XGlue IMPORT Event, mx_become_wm, mx_window_attrs, mx_size_hints,
                  mx_wm_hints, mx_configure_window, mx_send_client_message ;
FROM XServer IMPORT dpy, root, width, height ;
FROM Clients IMPORT Client, Kind, AllDesktops ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
IMPORT Clients, Frames, Ewmh, Atoms, Props, Log ;

CONST
  RootMask = SubstructureRedirectMask + SubstructureNotifyMask +
             PropertyChangeMask + StructureNotifyMask + ButtonPressMask ;
  ClientMask = PropertyChangeMask + FocusChangeMask ;
  MotifDecorations = 2 ;
  CascadeStep = 24 ;

TYPE
  Longs = POINTER TO ARRAY [0..65535] OF LONGCARD ;

VAR
  focused: Client ;
  currentDesktop, desktopCount: INTEGER ;
  workX, workY, workWidth, workHeight: INTEGER ;
  cascade: INTEGER ;
  lastTime: Time ;
  scanning: BOOLEAN ;

PROCEDURE HasBit (mask: LONGCARD; bit: LONGCARD) : BOOLEAN ;
BEGIN
  RETURN (mask DIV bit) MOD 2 = 1
END HasBit ;

PROCEDURE Reparented (c: Client) : BOOLEAN ;
BEGIN
  RETURN c^.frame # c^.window
END Reparented ;

PROCEDURE Visible (c: Client) : BOOLEAN ;
BEGIN
  RETURN (NOT c^.minimized) AND
         ((c^.desktop = currentDesktop) OR (c^.desktop = AllDesktops))
END Visible ;

PROCEDURE SetWmState (c: Client; state: LONGCARD) ;
VAR
  v: ARRAY [0..1] OF LONGCARD ;
BEGIN
  v[0] := state ;
  v[1] := None ;
  Props.SetCardinals (c^.window, Atoms.WmState, Atoms.WmState, v, 2)
END SetWmState ;

(* map or unmap the frame to match desktop and minimized state *)
PROCEDURE Show (c: Client) ;
BEGIN
  IF NOT Reparented (c)
  THEN
    RETURN
  END ;
  IF Visible (c)
  THEN
    IF XMapWindow (dpy, c^.frame) = 0 THEN END
  ELSE
    IF XUnmapWindow (dpy, c^.frame) = 0 THEN END
  END
END Show ;

PROCEDURE Put (list: Longs; VAR n: CARDINAL; c: Client) ;
BEGIN
  list^[n] := c^.frame ;
  INC (n)
END Put ;

PROCEDURE Restack ;
VAR
  list: Longs ;
  c: Client ;
  n, size: CARDINAL ;
BEGIN
  IF Clients.count = 0
  THEN
    RETURN
  END ;
  size := Clients.count * TSIZE (LONGCARD) ;
  ALLOCATE (list, size) ;
  n := 0 ;
  IF (focused # NIL) AND focused^.fullscreen
  THEN
    Put (list, n, focused)
  END ;
  c := Clients.stackTop ;
  WHILE c # NIL DO
    IF c^.kind = Dock THEN Put (list, n, c) END ;
    c := c^.stackNext
  END ;
  c := Clients.stackTop ;
  WHILE c # NIL DO
    IF ((c^.kind = Normal) OR (c^.kind = Dialog)) AND
       NOT ((c = focused) AND c^.fullscreen)
    THEN
      Put (list, n, c)
    END ;
    c := c^.stackNext
  END ;
  c := Clients.stackTop ;
  WHILE c # NIL DO
    IF c^.kind = DesktopKind THEN Put (list, n, c) END ;
    c := c^.stackNext
  END ;
  IF XRestackWindows (dpy, list, n) = 0 THEN END ;
  DEALLOCATE (list, size) ;
  Ewmh.UpdateClientList
END Restack ;

(* raise c and keep its transients above it *)
PROCEDURE RaiseClient (c: Client) ;
VAR
  t: Client ;
BEGIN
  Clients.Raise (c) ;
  t := Clients.first ;
  WHILE t # NIL DO
    IF (t^.transientFor = c^.window) AND (t # c)
    THEN
      Clients.Raise (t)
    END ;
    t := t^.next
  END ;
  Restack
END RaiseClient ;

PROCEDURE GrabClicks (c: Client) ;
BEGIN
  IF XGrabButton (dpy, AnyButton, AnyModifier, c^.window, False,
                  ButtonPressMask, GrabModeSync, GrabModeAsync,
                  None, None) = 0 THEN END
END GrabClicks ;

PROCEDURE UngrabClicks (c: Client) ;
BEGIN
  IF XUngrabButton (dpy, AnyButton, AnyModifier, c^.window) = 0 THEN END
END UngrabClicks ;

PROCEDURE SendProtocol (c: Client; protocol: Atom) ;
BEGIN
  mx_send_client_message (dpy, c^.window, c^.window, Atoms.WmProtocols, 0,
                          protocol, lastTime, 0, 0, 0)
END SendProtocol ;

PROCEDURE Focus (c: Client) ;
VAR
  old: Client ;
BEGIN
  IF (c # NIL) AND ((NOT Visible (c)) OR (c^.kind = Dock) OR
                    (c^.kind = DesktopKind))
  THEN
    c := NIL
  END ;
  old := focused ;
  focused := c ;
  IF (old # NIL) AND (old # c)
  THEN
    Frames.Draw (old, FALSE) ;
    GrabClicks (old)
  END ;
  IF c = NIL
  THEN
    IF XSetInputFocus (dpy, Ewmh.checkWindow, RevertToPointerRoot,
                       lastTime) = 0 THEN END ;
    Ewmh.SetActive (None) ;
    RETURN
  END ;
  Clients.Touch (c) ;
  IF c^.urgent
  THEN
    c^.urgent := FALSE ;
    Ewmh.SetClientState (c)
  END ;
  Frames.Draw (c, TRUE) ;
  UngrabClicks (c) ;
  IF c^.acceptsInput
  THEN
    IF XSetInputFocus (dpy, c^.window, RevertToPointerRoot,
                       lastTime) = 0 THEN END
  END ;
  IF c^.takeFocus
  THEN
    SendProtocol (c, Atoms.WmTakeFocus)
  END ;
  Ewmh.SetActive (c^.window)
END Focus ;

(* focus the most recently used window still visible here *)
PROCEDURE FocusFallback ;
VAR
  c: Client ;
BEGIN
  c := Clients.focusFirst ;
  WHILE (c # NIL) AND
        ((NOT Visible (c)) OR (c^.kind = Dock) OR (c^.kind = DesktopKind)) DO
    c := c^.focusNext
  END ;
  Focus (c)
END FocusFallback ;

PROCEDURE Close (c: Client) ;
BEGIN
  IF c^.deleteWindow
  THEN
    SendProtocol (c, Atoms.WmDeleteWindow)
  ELSE
    IF XKillClient (dpy, c^.window) = 0 THEN END
  END
END Close ;

PROCEDURE ReadTitle (c: Client) ;
BEGIN
  IF NOT Props.GetTitle (c^.window, c^.title)
  THEN
    c^.title[0] := 0C
  END
END ReadTitle ;

PROCEDURE ReadSizeHints (c: Client) ;
VAR
  h: ARRAY [0..8] OF INTEGER ;
BEGIN
  IF mx_size_hints (dpy, c^.window, h) # 0 THEN END ;
  c^.minWidth := h[0] ; c^.minHeight := h[1] ;
  c^.maxWidth := h[2] ; c^.maxHeight := h[3] ;
  c^.incWidth := h[4] ; c^.incHeight := h[5] ;
  c^.baseWidth := h[6] ; c^.baseHeight := h[7]
END ReadSizeHints ;

PROCEDURE UserPositioned (c: Client) : BOOLEAN ;
VAR
  h: ARRAY [0..8] OF INTEGER ;
BEGIN
  IF mx_size_hints (dpy, c^.window, h) = 0
  THEN
    RETURN FALSE
  END ;
  RETURN h[8] # 0
END UserPositioned ;

PROCEDURE ReadWmHints (c: Client) : INTEGER ;
VAR
  input, urgent, state: INTEGER ;
BEGIN
  IF mx_wm_hints (dpy, c^.window, input, urgent, state) # 0 THEN END ;
  c^.acceptsInput := input # 0 ;
  c^.urgent := (urgent # 0) AND (c # focused) ;
  RETURN state
END ReadWmHints ;

PROCEDURE ReadProtocols (c: Client) ;
VAR
  list: ADDRESS ;
  atoms: Longs ;
  n, i: INTEGER ;
BEGIN
  c^.deleteWindow := FALSE ;
  c^.takeFocus := FALSE ;
  IF XGetWMProtocols (dpy, c^.window, list, n) = 0
  THEN
    RETURN
  END ;
  atoms := list ;
  FOR i := 0 TO n - 1 DO
    IF atoms^[i] = Atoms.WmDeleteWindow THEN c^.deleteWindow := TRUE END ;
    IF atoms^[i] = Atoms.WmTakeFocus THEN c^.takeFocus := TRUE END
  END ;
  IF XFree (list) = 0 THEN END
END ReadProtocols ;

PROCEDURE ReadType (c: Client) ;
VAR
  types: ARRAY [0..15] OF LONGCARD ;
  n, i: CARDINAL ;
  t: LONGCARD ;
BEGIN
  n := Props.GetCardinals (c^.window, Atoms.NetWmWindowType, XA_ATOM, types) ;
  FOR i := 1 TO n DO
    t := types[i - 1] ;
    IF t = Atoms.NetWmWindowTypeDock
    THEN
      c^.kind := Dock ; RETURN
    ELSIF t = Atoms.NetWmWindowTypeDesktop
    THEN
      c^.kind := DesktopKind ; RETURN
    ELSIF t = Atoms.NetWmWindowTypeDialog
    THEN
      c^.kind := Dialog ; RETURN
    ELSIF t = Atoms.NetWmWindowTypeSplash
    THEN
      c^.decorated := FALSE ; RETURN
    ELSIF (t = Atoms.NetWmWindowTypeNormal) OR
          (t = Atoms.NetWmWindowTypeUtility)
    THEN
      RETURN
    END
  END ;
  IF c^.transientFor # None
  THEN
    c^.kind := Dialog
  END
END ReadType ;

PROCEDURE ReadMotifHints (c: Client) ;
VAR
  h: ARRAY [0..4] OF LONGCARD ;
BEGIN
  IF (Props.GetCardinals (c^.window, Atoms.MotifWmHints, Atoms.MotifWmHints,
                          h) >= 3) AND HasBit (h[0], MotifDecorations) AND
     (h[2] = 0)
  THEN
    c^.decorated := FALSE
  END
END ReadMotifHints ;

PROCEDURE ReadStrut (c: Client) ;
VAR
  s: ARRAY [0..11] OF LONGCARD ;
  i: CARDINAL ;
BEGIN
  IF (Props.GetCardinals (c^.window, Atoms.NetWmStrutPartial, XA_CARDINAL,
                          s) < 4) AND
     (Props.GetCardinals (c^.window, Atoms.NetWmStrut, XA_CARDINAL, s) < 4)
  THEN
    s[0] := 0 ; s[1] := 0 ; s[2] := 0 ; s[3] := 0
  END ;
  FOR i := 0 TO 3 DO
    (* refuse struts that would swallow the screen *)
    IF s[i] > VAL (LONGCARD, height DIV 2)
    THEN
      c^.strut[i] := 0
    ELSE
      c^.strut[i] := VAL (INTEGER, s[i])
    END
  END
END ReadStrut ;

PROCEDURE UpdateWorkarea ;
VAR
  c: Client ;
  left, right, top, bottom: INTEGER ;
BEGIN
  left := 0 ; right := 0 ; top := 0 ; bottom := 0 ;
  c := Clients.first ;
  WHILE c # NIL DO
    IF c^.kind = Dock
    THEN
      IF c^.strut[0] > left THEN left := c^.strut[0] END ;
      IF c^.strut[1] > right THEN right := c^.strut[1] END ;
      IF c^.strut[2] > top THEN top := c^.strut[2] END ;
      IF c^.strut[3] > bottom THEN bottom := c^.strut[3] END
    END ;
    c := c^.next
  END ;
  workX := left ;
  workY := top ;
  workWidth := width - left - right ;
  workHeight := height - top - bottom ;
  Ewmh.SetWorkarea (desktopCount, workX, workY, workWidth, workHeight)
END UpdateWorkarea ;

(* keep the frame inside the work area, shrinking it if needed *)
PROCEDURE Fit (c: Client) ;
VAR
  w, h: INTEGER ;
BEGIN
  IF c^.width + Frames.ExtraWidth (c) > workWidth
  THEN
    c^.width := workWidth - Frames.ExtraWidth (c)
  END ;
  IF c^.height + Frames.ExtraHeight (c) > workHeight
  THEN
    c^.height := workHeight - Frames.ExtraHeight (c)
  END ;
  w := c^.width ;
  h := c^.height ;
  Frames.Constrain (c, w, h) ;
  c^.width := w ;
  c^.height := h ;
  IF c^.x + c^.width + Frames.ExtraWidth (c) > workX + workWidth
  THEN
    c^.x := workX + workWidth - c^.width - Frames.ExtraWidth (c)
  END ;
  IF c^.y + c^.height + Frames.ExtraHeight (c) > workY + workHeight
  THEN
    c^.y := workY + workHeight - c^.height - Frames.ExtraHeight (c)
  END ;
  IF c^.x < workX THEN c^.x := workX END ;
  IF c^.y < workY THEN c^.y := workY END
END Fit ;

PROCEDURE Place (c: Client) ;
VAR
  parent: Client ;
BEGIN
  parent := NIL ;
  IF c^.transientFor # None
  THEN
    parent := Clients.Find (c^.transientFor)
  END ;
  IF (parent # NIL) AND (parent^.frame # parent^.window)
  THEN
    c^.x := parent^.x + (parent^.width + Frames.ExtraWidth (parent) -
                         c^.width - Frames.ExtraWidth (c)) DIV 2 ;
    c^.y := parent^.y + (parent^.height + Frames.ExtraHeight (parent) -
                         c^.height - Frames.ExtraHeight (c)) DIV 2
  ELSIF NOT (scanning OR UserPositioned (c))
  THEN
    c^.x := workX + CascadeStep + cascade * CascadeStep ;
    c^.y := workY + CascadeStep + cascade * CascadeStep ;
    cascade := (cascade + 1) MOD 8
  END ;
  Fit (c)
END Place ;

PROCEDURE Manage (w: Window) ;
VAR
  c, parent: Client ;
  x, y, cw, ch, mapState, override, state: INTEGER ;
  desk: LONGCARD ;
BEGIN
  IF (w = Ewmh.checkWindow) OR (Clients.Find (w) # NIL) OR
     (Clients.FindFrame (w) # NIL)
  THEN
    RETURN
  END ;
  IF (mx_window_attrs (dpy, w, x, y, cw, ch, mapState, override) = 0) OR
     (override # 0)
  THEN
    RETURN
  END ;
  c := Clients.New (w) ;
  c^.x := x ; c^.y := y ;
  c^.width := cw ; c^.height := ch ;
  IF XGetTransientForHint (dpy, w, c^.transientFor) = 0
  THEN
    c^.transientFor := None
  END ;
  ReadType (c) ;
  ReadMotifHints (c) ;
  ReadProtocols (c) ;
  ReadTitle (c) ;
  ReadSizeHints (c) ;
  state := ReadWmHints (c) ;
  c^.desktop := currentDesktop ;
  parent := NIL ;
  IF c^.transientFor # None
  THEN
    parent := Clients.Find (c^.transientFor)
  END ;
  IF parent # NIL
  THEN
    c^.desktop := parent^.desktop
  ELSIF Props.GetCardinal (w, Atoms.NetWmDesktop, XA_CARDINAL, desk)
  THEN
    IF desk = 0FFFFFFFFH
    THEN
      c^.desktop := AllDesktops
    ELSIF desk < VAL (LONGCARD, desktopCount)
    THEN
      c^.desktop := VAL (INTEGER, desk)
    END
  END ;
  IF XSelectInput (dpy, w, ClientMask) = 0 THEN END ;
  IF (c^.kind = Dock) OR (c^.kind = DesktopKind)
  THEN
    (* docks and desktop windows stay unframed on every desktop *)
    c^.frame := w ;
    c^.decorated := FALSE ;
    c^.desktop := AllDesktops ;
    IF c^.kind = Dock
    THEN
      ReadStrut (c)
    END ;
    IF XMapWindow (dpy, w) = 0 THEN END ;
    SetWmState (c, NormalState) ;
    Ewmh.SetClientDesktop (c) ;
    UpdateWorkarea ;
    Restack ;
    RETURN
  END ;
  c^.minimized := state = IconicState ;
  IF scanning
  THEN
    (* keep an adopted client where it already is on screen *)
    c^.x := c^.x - Frames.Left (c) ;
    c^.y := c^.y - Frames.Top (c)
  END ;
  Place (c) ;
  Frames.Create (c) ;
  Frames.Apply (c) ;
  Frames.Draw (c, FALSE) ;
  GrabClicks (c) ;
  IF c^.minimized
  THEN
    SetWmState (c, IconicState)
  ELSE
    SetWmState (c, NormalState)
  END ;
  Ewmh.SetClientDesktop (c) ;
  Ewmh.SetClientState (c) ;
  Show (c) ;
  RaiseClient (c) ;
  IF Visible (c)
  THEN
    Focus (c)
  END
END Manage ;

PROCEDURE Unmanage (c: Client; alive, withdraw: BOOLEAN) ;
VAR
  wasFocused, wasDock: BOOLEAN ;
BEGIN
  wasFocused := c = focused ;
  wasDock := c^.kind = Dock ;
  IF wasFocused
  THEN
    focused := NIL
  END ;
  IF Reparented (c)
  THEN
    Frames.Release (c, alive)
  END ;
  IF alive
  THEN
    IF XSelectInput (dpy, c^.window, 0) = 0 THEN END ;
    IF withdraw
    THEN
      SetWmState (c, WithdrawnState) ;
      Ewmh.ClearClient (c)
    END
  END ;
  Clients.Remove (c) ;
  IF wasDock
  THEN
    UpdateWorkarea
  END ;
  Ewmh.UpdateClientList ;
  IF wasFocused
  THEN
    FocusFallback
  END
END Unmanage ;

PROCEDURE Activate (c: Client) ;
BEGIN
  IF c^.minimized
  THEN
    c^.minimized := FALSE ;
    SetWmState (c, NormalState) ;
    Ewmh.SetClientState (c) ;
    Show (c)
  END ;
  RaiseClient (c) ;
  Focus (c)
END Activate ;

PROCEDURE OnMapRequest (VAR e: Event) ;
VAR
  c: Client ;
BEGIN
  c := Clients.Find (e.window) ;
  IF c = NIL
  THEN
    Manage (e.window)
  ELSE
    Activate (c)
  END
END OnMapRequest ;

PROCEDURE OnUnmapNotify (VAR e: Event) ;
VAR
  c: Client ;
BEGIN
  c := Clients.Find (e.window) ;
  IF c = NIL
  THEN
    RETURN
  END ;
  (* our own reparenting unmaps arrive from the root and are ignored *)
  IF (NOT Reparented (c)) OR (e.subwindow = c^.frame) OR (e.sendEvent # 0)
  THEN
    Unmanage (c, TRUE, TRUE)
  END
END OnUnmapNotify ;

PROCEDURE OnDestroyNotify (VAR e: Event) ;
VAR
  c: Client ;
BEGIN
  c := Clients.Find (e.window) ;
  IF c # NIL
  THEN
    Unmanage (c, FALSE, FALSE)
  END
END OnDestroyNotify ;

PROCEDURE OnConfigureRequest (VAR e: Event) ;
VAR
  c: Client ;
  w, h: INTEGER ;
BEGIN
  c := Clients.Find (e.window) ;
  IF c = NIL
  THEN
    mx_configure_window (dpy, e.window, e.valueMask, e.x, e.y, e.width,
                         e.height, e.border, e.subwindow, e.detail) ;
    RETURN
  END ;
  IF NOT Reparented (c)
  THEN
    mx_configure_window (dpy, e.window, e.valueMask, e.x, e.y, e.width,
                         e.height, 0, e.subwindow, e.detail) ;
    RETURN
  END ;
  IF NOT (c^.fullscreen OR c^.maximized)
  THEN
    IF HasBit (e.valueMask, CWX) THEN c^.x := e.x END ;
    IF HasBit (e.valueMask, CWY) THEN c^.y := e.y END ;
    w := c^.width ;
    h := c^.height ;
    IF HasBit (e.valueMask, CWWidth) THEN w := e.width END ;
    IF HasBit (e.valueMask, CWHeight) THEN h := e.height END ;
    Frames.Constrain (c, w, h) ;
    c^.width := w ;
    c^.height := h
  END ;
  Frames.Apply (c) ;
  IF HasBit (e.valueMask, CWStackMode) AND (e.detail = Above) AND
     (e.subwindow = None) AND Visible (c)
  THEN
    RaiseClient (c)
  END
END OnConfigureRequest ;

PROCEDURE OnPropertyNotify (VAR e: Event) ;
VAR
  c: Client ;
  state: INTEGER ;
BEGIN
  c := Clients.Find (e.window) ;
  IF c = NIL
  THEN
    RETURN
  END ;
  IF (e.atom = XA_WM_NAME) OR (e.atom = Atoms.NetWmName)
  THEN
    ReadTitle (c) ;
    IF Reparented (c)
    THEN
      Frames.Draw (c, c = focused)
    END
  ELSIF e.atom = XA_WM_NORMAL_HINTS
  THEN
    ReadSizeHints (c)
  ELSIF e.atom = XA_WM_HINTS
  THEN
    state := ReadWmHints (c) ;
    Ewmh.SetClientState (c)
  ELSIF e.atom = XA_WM_TRANSIENT_FOR
  THEN
    IF XGetTransientForHint (dpy, c^.window, c^.transientFor) = 0
    THEN
      c^.transientFor := None
    END
  ELSIF e.atom = Atoms.WmProtocols
  THEN
    ReadProtocols (c)
  ELSIF (c^.kind = Dock) AND
        ((e.atom = Atoms.NetWmStrut) OR (e.atom = Atoms.NetWmStrutPartial))
  THEN
    ReadStrut (c) ;
    UpdateWorkarea
  END
END OnPropertyNotify ;

PROCEDURE OnClientMessage (VAR e: Event) ;
VAR
  c: Client ;
  ext: ARRAY [0..3] OF LONGCARD ;
BEGIN
  IF e.atom = Atoms.MosaicCommand
  THEN
    IF e.data[0] = Atoms.CommandLogout
    THEN
      quit := TRUE
    END ;
    RETURN
  ELSIF e.atom = Atoms.NetRequestFrameExtents
  THEN
    ext[0] := Frames.Border ;
    ext[1] := Frames.Border ;
    ext[2] := Frames.Border + Frames.TitleHeight ;
    ext[3] := Frames.Border ;
    Props.SetCardinals (e.window, Atoms.NetFrameExtents, XA_CARDINAL, ext, 4) ;
    RETURN
  END ;
  c := Clients.Find (e.window) ;
  IF c = NIL
  THEN
    RETURN
  END ;
  IF e.atom = Atoms.NetActiveWindow
  THEN
    Activate (c)
  ELSIF e.atom = Atoms.NetCloseWindow
  THEN
    Close (c)
  END
END OnClientMessage ;

PROCEDURE OnButtonPress (VAR e: Event) ;
VAR
  c: Client ;
BEGIN
  c := Clients.Find (e.window) ;
  IF c # NIL
  THEN
    (* click on an unfocused client: focus it and pass the click on *)
    Activate (c) ;
    IF XAllowEvents (dpy, ReplayPointer, e.time) = 0 THEN END ;
    RETURN
  END ;
  c := Clients.FindFrame (e.window) ;
  IF (c # NIL) AND Reparented (c)
  THEN
    Activate (c)
  END
END OnButtonPress ;

PROCEDURE OnExpose (VAR e: Event) ;
VAR
  c: Client ;
BEGIN
  IF e.detail # 0
  THEN
    RETURN
  END ;
  c := Clients.FindFrame (e.window) ;
  IF (c # NIL) AND Reparented (c)
  THEN
    Frames.Draw (c, c = focused)
  END
END OnExpose ;

PROCEDURE Handle (VAR e: Event) ;
BEGIN
  CASE e.type OF
    KeyPress, KeyRelease, ButtonPress, ButtonRelease, MotionNotify,
    PropertyNotify:
      IF e.time # 0 THEN lastTime := e.time END
  ELSE
  END ;
  CASE e.type OF
    MapRequest: OnMapRequest (e) |
    UnmapNotify: OnUnmapNotify (e) |
    DestroyNotify: OnDestroyNotify (e) |
    ConfigureRequest: OnConfigureRequest (e) |
    PropertyNotify: OnPropertyNotify (e) |
    ClientMessage: OnClientMessage (e) |
    ButtonPress: OnButtonPress (e) |
    Expose: OnExpose (e)
  ELSE
  END
END Handle ;

PROCEDURE ScanExisting ;
VAR
  rootRet, parentRet: Window ;
  children: ADDRESS ;
  list: Longs ;
  n, i: CARDINAL ;
  x, y, w, h, mapState, override: INTEGER ;
  state: LONGCARD ;
BEGIN
  IF XQueryTree (dpy, root, rootRet, parentRet, children, n) = 0
  THEN
    RETURN
  END ;
  scanning := TRUE ;
  list := children ;
  FOR i := 1 TO n DO
    IF (mx_window_attrs (dpy, list^[i - 1], x, y, w, h, mapState,
                         override) # 0) AND (override = 0)
    THEN
      IF (mapState = IsViewable) OR
         (Props.GetCardinal (list^[i - 1], Atoms.WmState, Atoms.WmState,
                             state) AND (state = IconicState))
      THEN
        Manage (list^[i - 1])
      END
    END
  END ;
  scanning := FALSE ;
  IF children # NIL
  THEN
    IF XFree (children) = 0 THEN END
  END
END ScanExisting ;

PROCEDURE Start () : BOOLEAN ;
BEGIN
  IF mx_become_wm (dpy, root, RootMask) = 0
  THEN
    Log.Error ("another window manager is already running") ;
    RETURN FALSE
  END ;
  Ewmh.Setup (desktopCount) ;
  UpdateWorkarea ;
  IF XGrabServer (dpy) = 0 THEN END ;
  ScanExisting ;
  IF XUngrabServer (dpy) = 0 THEN END ;
  FocusFallback ;
  RETURN TRUE
END Start ;

PROCEDURE Stop ;
VAR
  c: Client ;
BEGIN
  WHILE Clients.first # NIL DO
    c := Clients.first ;
    Unmanage (c, TRUE, FALSE)
  END ;
  IF XSetInputFocus (dpy, 1 (* PointerRoot *), RevertToPointerRoot,
                     CurrentTime) = 0 THEN END ;
  Ewmh.Teardown ;
  IF XSelectInput (dpy, root, 0) = 0 THEN END ;
  IF XSync (dpy, False) = 0 THEN END
END Stop ;

BEGIN
  quit := FALSE ;
  focused := NIL ;
  currentDesktop := 0 ;
  desktopCount := 1 ;
  cascade := 0 ;
  lastTime := CurrentTime ;
  scanning := FALSE
END Wm.
