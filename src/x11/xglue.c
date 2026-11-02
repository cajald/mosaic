/* thin glue for xlib parts that modula-2 cannot reach cleanly:
   the XEvent union, variadic calls, callbacks and struct-heavy hints */

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <stdio.h>
#include <string.h>

typedef struct {
	int type, send_event;
	unsigned long window, subwindow, atom;
	int x, y, width, height, border, x_root, y_root;
	unsigned int state, detail;
	unsigned long time, value_mask;
	int override_redirect, format;
	long data[5];
	XEvent raw;
} mx_event;

_Static_assert(sizeof(XEvent) == 24 * sizeof(long), "unexpected XEvent size");
_Static_assert(sizeof(mx_event) == 328, "mx_event layout drifted from XGlue.def");

static void decode(XEvent *e, mx_event *m)
{
	memset(m, 0, sizeof *m);
	m->raw = *e;
	m->type = e->type;
	m->send_event = e->xany.send_event;
	m->window = e->xany.window;

	switch (e->type) {
	case KeyPress:
	case KeyRelease:
		m->subwindow = e->xkey.subwindow;
		m->x = e->xkey.x; m->y = e->xkey.y;
		m->x_root = e->xkey.x_root; m->y_root = e->xkey.y_root;
		m->state = e->xkey.state; m->detail = e->xkey.keycode;
		m->time = e->xkey.time;
		break;
	case ButtonPress:
	case ButtonRelease:
		m->subwindow = e->xbutton.subwindow;
		m->x = e->xbutton.x; m->y = e->xbutton.y;
		m->x_root = e->xbutton.x_root; m->y_root = e->xbutton.y_root;
		m->state = e->xbutton.state; m->detail = e->xbutton.button;
		m->time = e->xbutton.time;
		break;
	case MotionNotify:
		m->subwindow = e->xmotion.subwindow;
		m->x = e->xmotion.x; m->y = e->xmotion.y;
		m->x_root = e->xmotion.x_root; m->y_root = e->xmotion.y_root;
		m->state = e->xmotion.state; m->time = e->xmotion.time;
		break;
	case EnterNotify:
	case LeaveNotify:
		m->x = e->xcrossing.x; m->y = e->xcrossing.y;
		m->x_root = e->xcrossing.x_root; m->y_root = e->xcrossing.y_root;
		m->detail = e->xcrossing.detail; m->state = e->xcrossing.mode;
		m->time = e->xcrossing.time;
		break;
	case FocusIn:
	case FocusOut:
		m->detail = e->xfocus.detail; m->state = e->xfocus.mode;
		break;
	case Expose:
		m->x = e->xexpose.x; m->y = e->xexpose.y;
		m->width = e->xexpose.width; m->height = e->xexpose.height;
		m->detail = e->xexpose.count;
		break;
	case CreateNotify:
		m->window = e->xcreatewindow.window;
		m->subwindow = e->xcreatewindow.parent;
		m->override_redirect = e->xcreatewindow.override_redirect;
		break;
	case DestroyNotify:
		m->window = e->xdestroywindow.window;
		m->subwindow = e->xdestroywindow.event;
		break;
	case UnmapNotify:
		m->window = e->xunmap.window;
		m->subwindow = e->xunmap.event;
		break;
	case MapNotify:
		m->window = e->xmap.window;
		m->subwindow = e->xmap.event;
		m->override_redirect = e->xmap.override_redirect;
		break;
	case MapRequest:
		m->window = e->xmaprequest.window;
		m->subwindow = e->xmaprequest.parent;
		break;
	case ReparentNotify:
		m->window = e->xreparent.window;
		m->subwindow = e->xreparent.parent;
		break;
	case ConfigureNotify:
		m->window = e->xconfigure.window;
		m->subwindow = e->xconfigure.above;
		m->x = e->xconfigure.x; m->y = e->xconfigure.y;
		m->width = e->xconfigure.width; m->height = e->xconfigure.height;
		m->border = e->xconfigure.border_width;
		m->override_redirect = e->xconfigure.override_redirect;
		break;
	case ConfigureRequest:
		m->window = e->xconfigurerequest.window;
		m->subwindow = e->xconfigurerequest.above;
		m->x = e->xconfigurerequest.x; m->y = e->xconfigurerequest.y;
		m->width = e->xconfigurerequest.width;
		m->height = e->xconfigurerequest.height;
		m->border = e->xconfigurerequest.border_width;
		m->detail = e->xconfigurerequest.detail;
		m->value_mask = e->xconfigurerequest.value_mask;
		break;
	case PropertyNotify:
		m->atom = e->xproperty.atom;
		m->state = e->xproperty.state;
		m->time = e->xproperty.time;
		break;
	case SelectionClear:
		m->atom = e->xselectionclear.selection;
		m->time = e->xselectionclear.time;
		break;
	case ClientMessage:
		m->atom = e->xclient.message_type;
		m->format = e->xclient.format;
		memcpy(m->data, e->xclient.data.l, sizeof m->data);
		break;
	case MappingNotify:
		XRefreshKeyboardMapping(&e->xmapping);
		break;
	}
}

/* returns 0 when the event was consumed by the input method */
int mx_next_event(Display *dpy, mx_event *m)
{
	XEvent e;

	XNextEvent(dpy, &e);
	if (XFilterEvent(&e, None))
		return 0;
	decode(&e, m);
	return 1;
}

/* fold queued pointer motion for one window into the newest event */
void mx_compress_motion(Display *dpy, mx_event *m)
{
	XEvent e;
	int found = 0;

	while (XCheckTypedWindowEvent(dpy, m->window, MotionNotify, &e))
		found = 1;
	if (found)
		decode(&e, m);
}

static int error_count;
static int last_error;
static int verbose_errors = 1;

static int log_error(Display *dpy, XErrorEvent *e)
{
	char text[128];

	error_count++;
	last_error = e->error_code;
	if (verbose_errors) {
		XGetErrorText(dpy, e->error_code, text, sizeof text);
		fprintf(stderr, "mosaic: x error: %s (request %d.%d, resource 0x%lx)\n",
			text, e->request_code, e->minor_code, e->resourceid);
	}
	return 0;
}

void mx_install_error_handler(void)
{
	XSetErrorHandler(log_error);
}

/* errors on vanished client windows are routine and need no log line */
void mx_quiet_errors(int quiet)
{
	verbose_errors = !quiet;
}

int mx_error_count(void)
{
	return error_count;
}

static int redirect_refused;

static int detect_wm(Display *dpy, XErrorEvent *e)
{
	(void)dpy;
	if (e->error_code == BadAccess)
		redirect_refused = 1;
	return 0;
}

/* select substructure redirect on the root; fails if another wm owns it */
int mx_become_wm(Display *dpy, Window root, long mask)
{
	XErrorHandler old;

	redirect_refused = 0;
	XSync(dpy, False);
	old = XSetErrorHandler(detect_wm);
	XSelectInput(dpy, root, mask);
	XSync(dpy, False);
	XSetErrorHandler(old);
	return !redirect_refused;
}

int mx_window_attrs(Display *dpy, Window w, int *x, int *y, int *width,
		    int *height, int *map_state, int *override_redirect)
{
	XWindowAttributes a;

	if (!XGetWindowAttributes(dpy, w, &a))
		return 0;
	*x = a.x; *y = a.y; *width = a.width; *height = a.height;
	*map_state = a.map_state;
	*override_redirect = a.override_redirect;
	return 1;
}

/* out: min w/h, max w/h, inc w/h, base w/h; zero means unset */
int mx_size_hints(Display *dpy, Window w, int out[8])
{
	XSizeHints h;
	long supplied;

	memset(out, 0, 8 * sizeof(int));
	if (!XGetWMNormalHints(dpy, w, &h, &supplied))
		return 0;
	if (h.flags & PMinSize) { out[0] = h.min_width; out[1] = h.min_height; }
	if (h.flags & PMaxSize) { out[2] = h.max_width; out[3] = h.max_height; }
	if (h.flags & PResizeInc) { out[4] = h.width_inc; out[5] = h.height_inc; }
	if (h.flags & PBaseSize) { out[6] = h.base_width; out[7] = h.base_height; }
	else if (h.flags & PMinSize) { out[6] = h.min_width; out[7] = h.min_height; }
	return 1;
}

void mx_set_size_hints(Display *dpy, Window w, int minw, int minh,
		       int maxw, int maxh)
{
	XSizeHints h;

	memset(&h, 0, sizeof h);
	if (minw > 0 || minh > 0) {
		h.flags |= PMinSize; h.min_width = minw; h.min_height = minh;
	}
	if (maxw > 0 || maxh > 0) {
		h.flags |= PMaxSize; h.max_width = maxw; h.max_height = maxh;
	}
	XSetWMNormalHints(dpy, w, &h);
}

/* input: accepts focus; state: initial state or -1 */
int mx_wm_hints(Display *dpy, Window w, int *input, int *urgent, int *state)
{
	XWMHints *h = XGetWMHints(dpy, w);

	*input = 1; *urgent = 0; *state = -1;
	if (!h)
		return 0;
	if (h->flags & InputHint)
		*input = h->input;
	if (h->flags & XUrgencyHint)
		*urgent = 1;
	if (h->flags & StateHint)
		*state = h->initial_state;
	XFree(h);
	return 1;
}

void mx_set_override_redirect(Display *dpy, Window w, int on)
{
	XSetWindowAttributes a;

	a.override_redirect = on;
	XChangeWindowAttributes(dpy, w, CWOverrideRedirect, &a);
}

void mx_set_bit_gravity(Display *dpy, Window w, int gravity)
{
	XSetWindowAttributes a;

	a.bit_gravity = gravity;
	XChangeWindowAttributes(dpy, w, CWBitGravity, &a);
}

void mx_configure_window(Display *dpy, Window w, unsigned int mask, int x,
			 int y, int width, int height, int border,
			 Window sibling, int stack_mode)
{
	XWindowChanges c;

	c.x = x; c.y = y; c.width = width; c.height = height;
	c.border_width = border; c.sibling = sibling; c.stack_mode = stack_mode;
	XConfigureWindow(dpy, w, mask, &c);
}

/* ICCCM 4.1.5: tell the client its real root-relative geometry */
void mx_send_configure_notify(Display *dpy, Window w, int x, int y,
			      int width, int height)
{
	XConfigureEvent c;

	memset(&c, 0, sizeof c);
	c.type = ConfigureNotify;
	c.display = dpy;
	c.event = w;
	c.window = w;
	c.x = x; c.y = y; c.width = width; c.height = height;
	c.border_width = 0;
	c.above = None;
	c.override_redirect = False;
	XSendEvent(dpy, w, False, StructureNotifyMask, (XEvent *)&c);
}

void mx_send_client_message(Display *dpy, Window dest, Window w, Atom type,
			    long mask, long d0, long d1, long d2, long d3,
			    long d4)
{
	XEvent e;

	memset(&e, 0, sizeof e);
	e.xclient.type = ClientMessage;
	e.xclient.window = w;
	e.xclient.message_type = type;
	e.xclient.format = 32;
	e.xclient.data.l[0] = d0; e.xclient.data.l[1] = d1;
	e.xclient.data.l[2] = d2; e.xclient.data.l[3] = d3;
	e.xclient.data.l[4] = d4;
	XSendEvent(dpy, dest, False, mask, &e);
}

unsigned int mx_numlock_mask(Display *dpy)
{
	XModifierKeymap *map = XGetModifierMapping(dpy);
	KeyCode numlock = XKeysymToKeycode(dpy, XK_Num_Lock);
	unsigned int mask = 0;
	int i, j;

	if (!map)
		return 0;
	for (i = 0; i < 8; i++)
		for (j = 0; j < map->max_keypermod; j++)
			if (numlock && map->modifiermap[i * map->max_keypermod + j] == numlock)
				mask = 1u << i;
	XFreeModifiermap(map);
	return mask;
}

static XIM input_method;

/* returns an input context for text entry, or NULL without an input method */
XIC mx_create_ic(Display *dpy, Window w)
{
	if (!input_method) {
		XSetLocaleModifiers("");
		input_method = XOpenIM(dpy, NULL, NULL, NULL);
		if (!input_method)
			return NULL;
	}
	return XCreateIC(input_method, XNInputStyle,
			 XIMPreeditNothing | XIMStatusNothing,
			 XNClientWindow, w, XNFocusWindow, w, NULL);
}

void mx_destroy_ic(XIC ic)
{
	if (ic)
		XDestroyIC(ic);
}

void mx_close_im(void)
{
	if (input_method) {
		XCloseIM(input_method);
		input_method = NULL;
	}
}

/* utf-8 text and keysym of a key event; returns text length */
int mx_lookup_key(XIC ic, XEvent *raw, char *buf, int len, KeySym *sym)
{
	Status status;
	int n;

	*sym = NoSymbol;
	if (len <= 0)
		return 0;
	if (ic) {
		n = Xutf8LookupString(ic, &raw->xkey, buf, len - 1, sym, &status);
		if (status == XBufferOverflow || status == XLookupNone)
			n = 0;
		if (status == XLookupChars)
			*sym = NoSymbol;
	} else {
		n = XLookupString(&raw->xkey, buf, len - 1, sym, NULL);
		/* latin-1 bytes above ascii are not valid utf-8 */
		if (n == 1 && (unsigned char)buf[0] > 0x7f)
			n = 0;
	}
	if (n < 0)
		n = 0;
	buf[n] = '\0';
	return n;
}
