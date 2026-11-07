IMPLEMENTATION MODULE Dialog ;

FROM SYSTEM IMPORT ADR ;
FROM Xlib IMPORT Window, KeySym, None, XMapWindow, XSetTransientForHint,
                 Expose, ConfigureNotify, KeyPress, KeyRelease, ButtonPress,
                 ButtonRelease, MotionNotify, ClientMessage ;
FROM XGlue IMPORT Event ;
FROM XServer IMPORT dpy ;
FROM Menu IMPORT Dispatch ;
FROM Posix IMPORT mx_signal_pending ;
FROM Win IMPORT Handle ;
FROM Widgets IMPORT Button, TextField, Edit ;
FROM Gfx IMPORT Surface ;
IMPORT Win, Gfx, Widgets, Str, Atoms, XServer ;

CONST
  Width = 380 ;
  Margin = 14 ;
  ButtonWidth = 84 ;

TYPE
  Kind = (MessageKind, ConfirmKind, PromptKind) ;

VAR
  (* one dialog at a time, so the layout lives here *)
  message: ARRAY [0..1023] OF CHAR ;
  ok, cancel: Button ;
  field: TextField ;
  kind: Kind ;
  textHeight: INTEGER ;

PROCEDURE Layout (h: Handle) ;
VAR
  buttonY: INTEGER ;
BEGIN
  buttonY := h^.height - Margin - Widgets.ButtonHeight ;
  ok.x := h^.width - Margin - ButtonWidth ;
  ok.y := buttonY ;
  cancel.x := ok.x - 12 - ButtonWidth ;
  cancel.y := buttonY ;
  field.x := Margin ;
  field.y := Margin + textHeight + 6 ;
  field.w := h^.width - 2 * Margin
END Layout ;

PROCEDURE Draw (h: Handle) ;
VAR
  s: Surface ;
BEGIN
  s := h^.surface ;
  Layout (h) ;
  Widgets.DrawPanel (s, 0, 0, h^.width, h^.height) ;
  IF Widgets.DrawWrapped (s, Margin, Margin, h^.width - 2 * Margin, message) = 0
  THEN
  END ;
  IF kind = PromptKind
  THEN
    Widgets.DrawField (s, field)
  END ;
  Widgets.DrawButton (s, ok) ;
  IF kind # MessageKind
  THEN
    Widgets.DrawButton (s, cancel)
  END ;
  Gfx.Flush (s)
END Draw ;

PROCEDURE Run (owner: Window; title: ARRAY OF CHAR; k: Kind;
               okLabel: ARRAY OF CHAR; other: Dispatch) : BOOLEAN ;
VAR
  h: Handle ;
  e: Event ;
  height: INTEGER ;
  sym: KeySym ;
  key: ARRAY [0..31] OF CHAR ;
  done, result: BOOLEAN ;
  edit: Edit ;
BEGIN
  kind := k ;
  textHeight := Widgets.WrappedHeight (Width - 2 * Margin, message) ;
  height := Margin + textHeight + Margin + Widgets.ButtonHeight + Margin ;
  IF kind = PromptKind
  THEN
    INC (height, Widgets.FieldHeight + 6)
  END ;
  h := Win.Create (title, "mosaic-dialog", Width, height, Width, height) ;
  Win.SetType (h, Atoms.NetWmWindowTypeDialog) ;
  IF owner # None
  THEN
    IF XSetTransientForHint (dpy, h^.window, owner) = 0 THEN END
  END ;
  Widgets.SetButton (ok, okLabel, 0, 0, ButtonWidth) ;
  ok.isDefault := TRUE ;
  Widgets.SetButton (cancel, "Cancel", 0, 0, ButtonWidth) ;
  field.focused := TRUE ;
  IF XMapWindow (dpy, h^.window) = 0 THEN END ;
  done := FALSE ;
  result := FALSE ;
  WHILE NOT done DO
    IF mx_signal_pending () # 0
    THEN
      (* leave the program's main loop to handle termination *)
      done := TRUE
    ELSIF XServer.WaitEvent (1000) AND XServer.NextEvent (e)
    THEN
      IF e.window # h^.window
      THEN
        (* modal: input meant for other windows is dropped *)
        CASE e.type OF
          KeyPress, KeyRelease, ButtonPress, ButtonRelease, MotionNotify,
          ClientMessage:
        ELSE
          other (e)
        END
      ELSIF Win.IsClose (h, e)
      THEN
        done := TRUE
      ELSE
        CASE e.type OF
          Expose:
            IF e.detail = 0 THEN Draw (h) END |
          ConfigureNotify:
            IF Win.Configured (h, e) THEN Draw (h) END |
          ButtonPress:
            ok.down := Widgets.OnButton (ok, e.x, e.y) ;
            cancel.down := (kind # MessageKind) AND
                           Widgets.OnButton (cancel, e.x, e.y) ;
            Draw (h) |
          ButtonRelease:
            IF ok.down AND Widgets.OnButton (ok, e.x, e.y)
            THEN
              result := TRUE ;
              done := TRUE
            ELSIF cancel.down AND Widgets.OnButton (cancel, e.x, e.y)
            THEN
              done := TRUE
            END ;
            ok.down := FALSE ;
            cancel.down := FALSE ;
            Draw (h) |
          KeyPress:
            Win.Key (h, e, sym, key) ;
            IF kind = PromptKind
            THEN
              edit := Widgets.FieldKey (field, sym, key) ;
              IF edit = Widgets.EditEnter
              THEN
                result := TRUE ;
                done := TRUE
              ELSIF edit = Widgets.EditCancel
              THEN
                done := TRUE
              ELSIF edit # Widgets.EditNone
              THEN
                Draw (h)
              END
            ELSIF Widgets.IsEnter (sym)
            THEN
              result := TRUE ;
              done := TRUE
            ELSIF sym = Widgets.XKEscape
            THEN
              done := TRUE
            END
        ELSE
        END
      END
    END
  END ;
  Win.Destroy (h) ;
  RETURN result
END Run ;

PROCEDURE SetText (t: ARRAY OF CHAR) ;
BEGIN
  IF NOT Str.Assign (t, message)
  THEN
    Str.FromBytes (ADR (t), Str.Length (t), message)
  END
END SetText ;

PROCEDURE Message (owner: Window; title, text: ARRAY OF CHAR;
                   other: Dispatch) ;
BEGIN
  SetText (text) ;
  IF Run (owner, title, MessageKind, "OK", other) THEN END
END Message ;

PROCEDURE Confirm (owner: Window; title, text, action: ARRAY OF CHAR;
                   other: Dispatch) : BOOLEAN ;
BEGIN
  SetText (text) ;
  RETURN Run (owner, title, ConfirmKind, action, other)
END Confirm ;

PROCEDURE Prompt (owner: Window; title, text: ARRAY OF CHAR;
                  VAR value: ARRAY OF CHAR; other: Dispatch) : BOOLEAN ;
BEGIN
  SetText (text) ;
  Widgets.SetField (field, value) ;
  IF NOT Run (owner, title, PromptKind, "OK", other)
  THEN
    RETURN FALSE
  END ;
  RETURN Str.Assign (field.text, value)
END Prompt ;

END Dialog.
