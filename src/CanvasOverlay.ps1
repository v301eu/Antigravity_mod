param([switch]$CompileOnly)
# whisper_saver: Interactive Screen Snipping, Drawing & 768px RAM Compression Overlay
# Pure RAM operation (zero temporary files on disk). Ctrl+C compresses to max 768px, copies to Clipboard, and closes automatically.

$ErrorActionPreference = "Stop"

Add-Type -ReferencedAssemblies @(
    "System.Windows.Forms.dll",
    "System.Drawing.dll"
) -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class Win32DpiAndCapture {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern IntPtr GetDesktopWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindowDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern bool BitBlt(IntPtr hDest, int xDest, int yDest, int w, int h, IntPtr hSrc, int xSrc, int ySrc, int rop);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleDC(IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleBitmap(IntPtr hDC, int w, int h);

    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObj);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObj);

    public const int SRCCOPY = 0x00CC0020;
    public const int CAPTUREBLT = 0x40000000;

    public static Bitmap CaptureVirtualScreen(Rectangle bounds) {
        IntPtr hDesk = GetDesktopWindow();
        IntPtr hSrc = GetWindowDC(hDesk);
        IntPtr hDest = CreateCompatibleDC(hSrc);
        IntPtr hBmp = CreateCompatibleBitmap(hSrc, bounds.Width, bounds.Height);
        IntPtr hOld = SelectObject(hDest, hBmp);
        BitBlt(hDest, 0, 0, bounds.Width, bounds.Height, hSrc, bounds.X, bounds.Y, SRCCOPY | CAPTUREBLT);
        SelectObject(hDest, hOld);
        DeleteDC(hDest);
        ReleaseDC(hDesk, hSrc);
        Bitmap bmp = Image.FromHbitmap(hBmp);
        DeleteObject(hBmp);
        return bmp;
    }
}

public enum DrawTool {
    Pen,
    Highlighter,
    Arrow,
    Rectangle,
    Ellipse,
    Text
}

public class DrawAction {
    public DrawTool Tool;
    public Color StrokeColor;
    public float StrokeWidth;
    public List<Point> Points = new List<Point>();
    public Point Start;
    public Point End;
    public string TextContent;

    public void Render(Graphics g, Point offset) {
        Color c = (Tool == DrawTool.Highlighter) ? Color.FromArgb(95, StrokeColor) : StrokeColor;
        float w = (Tool == DrawTool.Highlighter) ? Math.Max(14f, StrokeWidth * 4.5f) : StrokeWidth;

        using (Pen pen = new Pen(c, w)) {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            pen.LineJoin = LineJoin.Round;

            if (Tool == DrawTool.Pen || Tool == DrawTool.Highlighter) {
                if (Points.Count == 1) {
                    using (SolidBrush sb = new SolidBrush(c)) {
                        g.FillEllipse(sb, Points[0].X + offset.X - w / 2f, Points[0].Y + offset.Y - w / 2f, w, w);
                    }
                } else if (Points.Count > 1) {
                    Point[] shifted = new Point[Points.Count];
                    for (int i = 0; i < Points.Count; i++) {
                        shifted[i] = new Point(Points[i].X + offset.X, Points[i].Y + offset.Y);
                    }
                    g.DrawLines(pen, shifted);
                }
            } else if (Tool == DrawTool.Arrow) {
                Point p1 = new Point(Start.X + offset.X, Start.Y + offset.Y);
                Point p2 = new Point(End.X + offset.X, End.Y + offset.Y);
                if (Math.Abs(p2.X - p1.X) > 2 || Math.Abs(p2.Y - p1.Y) > 2) {
                    AdjustableArrowCap cap = new AdjustableArrowCap(Math.Max(4.5f, w * 1.4f), Math.Max(5f, w * 1.6f), true);
                    pen.CustomEndCap = cap;
                    g.DrawLine(pen, p1, p2);
                }
            } else if (Tool == DrawTool.Rectangle) {
                Rectangle r = MakeRect(new Point(Start.X + offset.X, Start.Y + offset.Y), new Point(End.X + offset.X, End.Y + offset.Y));
                if (r.Width > 1 && r.Height > 1) g.DrawRectangle(pen, r);
            } else if (Tool == DrawTool.Ellipse) {
                Rectangle r = MakeRect(new Point(Start.X + offset.X, Start.Y + offset.Y), new Point(End.X + offset.X, End.Y + offset.Y));
                if (r.Width > 1 && r.Height > 1) g.DrawEllipse(pen, r);
            } else if (Tool == DrawTool.Text && !string.IsNullOrEmpty(TextContent)) {
                float fontSize = Math.Max(13f, StrokeWidth * 4.5f);
                using (Font f = new Font("Segoe UI Semibold", fontSize, FontStyle.Bold, GraphicsUnit.Pixel)) {
                    Point tp = new Point(Start.X + offset.X, Start.Y + offset.Y);
                    SizeF sz = g.MeasureString(TextContent, f);
                    using (SolidBrush bg = new SolidBrush(Color.FromArgb(165, 15, 23, 42))) {
                        g.FillRectangle(bg, tp.X - 3, tp.Y - 2, sz.Width + 6, sz.Height + 4);
                    }
                    using (SolidBrush tb = new SolidBrush(StrokeColor)) {
                        g.DrawString(TextContent, f, tb, tp);
                    }
                }
            }
        }
    }

    public static Rectangle MakeRect(Point a, Point b) {
        return new Rectangle(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
    }
}

public class WhisperCanvasForm : Form {
    private Bitmap _screenBmp;
    private Bitmap _dimmedBmp;
    private Rectangle _virtualBounds;

    private bool _hasSelection = false;
    private bool _isSelecting = false;
    private Point _selStart;
    private Rectangle _selection = Rectangle.Empty;

    private DrawTool _activeTool = DrawTool.Pen;
    private Color _activeColor = Color.FromArgb(255, 239, 68, 68); // Red default
    private float _activeWidth = 3.5f;

    private List<DrawAction> _actions = new List<DrawAction>();
    private DrawAction _currentAction = null;

    private FlowLayoutPanel _toolbar;
    private TextBox _inlineTextBox = null;
    private Point _inlineTextRelPos;
    private Point _mousePos;

    private List<Button> _toolButtons = new List<Button>();
    private List<Button> _colorButtons = new List<Button>();

    public bool CopiedToClipboard { get; private set; }

    public WhisperCanvasForm() {
        CopiedToClipboard = false;
        _virtualBounds = SystemInformation.VirtualScreen;
        _screenBmp = Win32DpiAndCapture.CaptureVirtualScreen(_virtualBounds);

        // Pre-build dimmed background in RAM for instant 60 FPS rendering
        _dimmedBmp = new Bitmap(_screenBmp.Width, _screenBmp.Height, PixelFormat.Format32bppPArgb);
        using (Graphics g = Graphics.FromImage(_dimmedBmp)) {
            g.DrawImage(_screenBmp, 0, 0, _screenBmp.Width, _screenBmp.Height);
            using (SolidBrush dimBrush = new SolidBrush(Color.FromArgb(135, 8, 12, 20))) {
                g.FillRectangle(dimBrush, 0, 0, _dimmedBmp.Width, _dimmedBmp.Height);
            }
        }

        this.FormBorderStyle = FormBorderStyle.None;
        this.StartPosition = FormStartPosition.Manual;
        this.Bounds = _virtualBounds;
        this.TopMost = true;
        this.ShowInTaskbar = false;
        this.KeyPreview = true;
        this.DoubleBuffered = true;
        this.SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        this.Cursor = Cursors.Cross;

        BuildToolbar();
    }

    private void BuildToolbar() {
        _toolbar = new FlowLayoutPanel();
        _toolbar.AutoSize = true;
        _toolbar.WrapContents = false;
        _toolbar.BackColor = Color.FromArgb(245, 20, 26, 38);
        _toolbar.Padding = new Padding(6, 5, 6, 5);
        _toolbar.Visible = false;
        _toolbar.Cursor = Cursors.Default;

        AddToolBtn("\u270F Pi\u00F3ro", DrawTool.Pen);
        AddToolBtn("\u2712 Marker", DrawTool.Highlighter);
        AddToolBtn("\u2197 Strza\u0142ka", DrawTool.Arrow);
        AddToolBtn("\u25AD Ramka", DrawTool.Rectangle);
        AddToolBtn("\u25EF K\u00F3\u0142ko", DrawTool.Ellipse);
        AddToolBtn("T Tekst", DrawTool.Text);

        AddSeparator();

        AddColorBtn(Color.FromArgb(255, 239, 68, 68));   // Red
        AddColorBtn(Color.FromArgb(255, 34, 197, 94));   // Green
        AddColorBtn(Color.FromArgb(255, 59, 130, 246));  // Blue
        AddColorBtn(Color.FromArgb(255, 250, 204, 21));  // Yellow
        AddColorBtn(Color.FromArgb(255, 255, 255, 255)); // White

        AddSeparator();

        Button sizeBtn = CreateFlatBtn("Grubo\u015B\u0107: M", Color.FromArgb(220, 230, 245));
        sizeBtn.Click += (s, e) => {
            CommitInlineText();
            if (_activeWidth < 3f) { _activeWidth = 3.5f; sizeBtn.Text = "Grubo\u015B\u0107: M"; }
            else if (_activeWidth < 6f) { _activeWidth = 7f; sizeBtn.Text = "Grubo\u015B\u0107: L"; }
            else { _activeWidth = 2f; sizeBtn.Text = "Grubo\u015B\u0107: S"; }
            this.Focus();
        };
        _toolbar.Controls.Add(sizeBtn);

        Button undoBtn = CreateFlatBtn("\u21A9 Cofnij (Ctrl+Z)", Color.FromArgb(200, 215, 235));
        undoBtn.Click += (s, e) => { UndoLast(); this.Focus(); };
        _toolbar.Controls.Add(undoBtn);

        Button reselectBtn = CreateFlatBtn("\u2702 Nowy obszar", Color.FromArgb(200, 215, 235));
        reselectBtn.Click += (s, e) => {
            CommitInlineText();
            _actions.Clear();
            _hasSelection = false;
            _selection = Rectangle.Empty;
            _toolbar.Visible = false;
            this.Invalidate();
            this.Focus();
        };
        _toolbar.Controls.Add(reselectBtn);

        Button copyBtn = CreateFlatBtn("\u2714 Kopiuj 768px (Ctrl+C)", Color.FromArgb(255, 255, 255));
        copyBtn.BackColor = Color.FromArgb(255, 37, 99, 235);
        copyBtn.FlatAppearance.BorderColor = Color.FromArgb(255, 96, 165, 250);
        copyBtn.Font = new Font("Segoe UI Semibold", 9.5f, FontStyle.Bold);
        copyBtn.Click += (s, e) => FinalizeAndCopy768();
        _toolbar.Controls.Add(copyBtn);

        Button cancelBtn = CreateFlatBtn("✕ Esc", Color.FromArgb(248, 113, 113));
        cancelBtn.Click += (s, e) => this.Close();
        _toolbar.Controls.Add(cancelBtn);

        UpdateToolbarHighlights();
        this.Controls.Add(_toolbar);
    }

    private Button CreateFlatBtn(string text, Color fore) {
        Button b = new Button();
        b.Text = text;
        b.AutoSize = true;
        b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderSize = 1;
        b.FlatAppearance.BorderColor = Color.FromArgb(90, 148, 163, 184);
        b.BackColor = Color.FromArgb(255, 30, 41, 59);
        b.ForeColor = fore;
        b.Font = new Font("Segoe UI", 9f, FontStyle.Regular);
        b.Margin = new Padding(2, 0, 2, 0);
        b.Padding = new Padding(4, 2, 4, 2);
        b.TabStop = false;
        return b;
    }

    private void AddToolBtn(string label, DrawTool tool) {
        Button b = CreateFlatBtn(label, Color.FromArgb(226, 232, 240));
        b.Tag = tool;
        b.Click += (s, e) => {
            CommitInlineText();
            _activeTool = tool;
            UpdateToolbarHighlights();
            this.Focus();
        };
        _toolButtons.Add(b);
        _toolbar.Controls.Add(b);
    }

    private void AddColorBtn(Color c) {
        Button b = new Button();
        b.Size = new Size(24, 26);
        b.FlatStyle = FlatStyle.Flat;
        b.BackColor = c;
        b.Tag = c;
        b.Margin = new Padding(2, 2, 2, 0);
        b.TabStop = false;
        b.Click += (s, e) => {
            _activeColor = c;
            UpdateToolbarHighlights();
            this.Focus();
        };
        _colorButtons.Add(b);
        _toolbar.Controls.Add(b);
    }

    private void AddSeparator() {
        Panel p = new Panel();
        p.Size = new Size(1, 24);
        p.BackColor = Color.FromArgb(90, 148, 163, 184);
        p.Margin = new Padding(5, 3, 5, 0);
        _toolbar.Controls.Add(p);
    }

    private void UpdateToolbarHighlights() {
        foreach (Button b in _toolButtons) {
            bool act = ((DrawTool)b.Tag == _activeTool);
            b.BackColor = act ? Color.FromArgb(255, 59, 130, 246) : Color.FromArgb(255, 30, 41, 59);
            b.ForeColor = act ? Color.White : Color.FromArgb(226, 232, 240);
        }
        foreach (Button b in _colorButtons) {
            bool act = (((Color)b.Tag).ToArgb() == _activeColor.ToArgb());
            b.FlatAppearance.BorderSize = act ? 2 : 1;
            b.FlatAppearance.BorderColor = act ? Color.White : Color.FromArgb(80, 0, 0, 0);
        }
    }

    private void PositionToolbar() {
        if (!_hasSelection) {
            _toolbar.Visible = false;
            return;
        }
        _toolbar.Visible = true;
        _toolbar.PerformLayout();
        int tx = Math.Max(8, Math.Min(this.Width - _toolbar.Width - 8, _selection.Right - _toolbar.Width));
        int ty = _selection.Bottom + 8;
        if (ty + _toolbar.Height > this.Height - 8) {
            ty = _selection.Top - _toolbar.Height - 8;
            if (ty < 8) ty = Math.Max(8, _selection.Bottom - _toolbar.Height - 8);
        }
        _toolbar.Location = new Point(tx, ty);
        _toolbar.BringToFront();
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Right) {
            if (_currentAction != null) {
                _currentAction = null;
                this.Invalidate();
            } else {
                this.Close();
            }
            return;
        }
        if (e.Button != MouseButtons.Left) return;

        CommitInlineText();

        if (!_hasSelection) {
            _isSelecting = true;
            _selStart = e.Location;
            _selection = new Rectangle(e.X, e.Y, 0, 0);
            this.Invalidate();
            return;
        }

        // Inside selection -> draw with active tool
        if (_selection.Contains(e.Location)) {
            Point rel = new Point(e.X - _selection.X, e.Y - _selection.Y);
            if (_activeTool == DrawTool.Text) {
                OpenInlineTextBox(e.Location, rel);
                return;
            }
            _currentAction = new DrawAction {
                Tool = _activeTool,
                StrokeColor = _activeColor,
                StrokeWidth = _activeWidth,
                Start = rel,
                End = rel
            };
            _currentAction.Points.Add(rel);
            this.Invalidate(_selection);
        }
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        base.OnMouseMove(e);
        _mousePos = e.Location;

        if (_isSelecting) {
            _selection = DrawAction.MakeRect(_selStart, e.Location);
            this.Invalidate();
            return;
        }

        if (_currentAction != null) {
            Point clamped = new Point(
                Math.Max(0, Math.Min(_selection.Width - 1, e.X - _selection.X)),
                Math.Max(0, Math.Min(_selection.Height - 1, e.Y - _selection.Y))
            );
            _currentAction.End = clamped;
            if (_currentAction.Tool == DrawTool.Pen || _currentAction.Tool == DrawTool.Highlighter) {
                _currentAction.Points.Add(clamped);
            }
            this.Invalidate(Rectangle.Inflate(_selection, 4, 4));
            return;
        }

        if (!_hasSelection) {
            this.Invalidate();
        }
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left) return;

        if (_isSelecting) {
            _isSelecting = false;
            _selection = DrawAction.MakeRect(_selStart, e.Location);
            if (_selection.Width >= 12 && _selection.Height >= 12) {
                _hasSelection = true;
                PositionToolbar();
            } else {
                _selection = Rectangle.Empty;
                _hasSelection = false;
            }
            this.Invalidate();
            return;
        }

        if (_currentAction != null) {
            _actions.Add(_currentAction);
            _currentAction = null;
            this.Invalidate(Rectangle.Inflate(_selection, 4, 4));
        }
    }

    private void OpenInlineTextBox(Point screenPt, Point relPt) {
        CommitInlineText();
        _inlineTextRelPos = relPt;
        _inlineTextBox = new TextBox();
        _inlineTextBox.BorderStyle = BorderStyle.FixedSingle;
        _inlineTextBox.BackColor = Color.FromArgb(30, 41, 59);
        _inlineTextBox.ForeColor = _activeColor;
        _inlineTextBox.Font = new Font("Segoe UI Semibold", Math.Max(13f, _activeWidth * 4.5f), FontStyle.Bold, GraphicsUnit.Pixel);
        _inlineTextBox.Location = screenPt;
        _inlineTextBox.Width = Math.Max(140, Math.Min(320, _selection.Right - screenPt.X - 4));
        _inlineTextBox.KeyDown += (s, ev) => {
            if (ev.KeyCode == Keys.Enter) {
                ev.SuppressKeyPress = true;
                CommitInlineText();
                this.Focus();
            } else if (ev.KeyCode == Keys.Escape) {
                ev.SuppressKeyPress = true;
                this.Controls.Remove(_inlineTextBox);
                _inlineTextBox.Dispose();
                _inlineTextBox = null;
                this.Focus();
            }
        };
        this.Controls.Add(_inlineTextBox);
        _inlineTextBox.BringToFront();
        _inlineTextBox.Focus();
    }

    private void CommitInlineText() {
        if (_inlineTextBox != null) {
            string txt = _inlineTextBox.Text.Trim();
            if (!string.IsNullOrEmpty(txt)) {
                _actions.Add(new DrawAction {
                    Tool = DrawTool.Text,
                    StrokeColor = _activeColor,
                    StrokeWidth = _activeWidth,
                    Start = _inlineTextRelPos,
                    TextContent = txt
                });
            }
            this.Controls.Remove(_inlineTextBox);
            _inlineTextBox.Dispose();
            _inlineTextBox = null;
            this.Invalidate();
        }
    }

    private void UndoLast() {
        CommitInlineText();
        if (_actions.Count > 0) {
            _actions.RemoveAt(_actions.Count - 1);
            this.Invalidate();
        }
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        base.OnKeyDown(e);
        if (_inlineTextBox != null && _inlineTextBox.Focused) return;

        if (e.KeyCode == Keys.Escape) {
            this.Close();
        } else if (e.Control && e.KeyCode == Keys.C) {
            e.SuppressKeyPress = true;
            FinalizeAndCopy768();
        } else if (e.KeyCode == Keys.Enter && _hasSelection) {
            e.SuppressKeyPress = true;
            FinalizeAndCopy768();
        } else if (e.Control && e.KeyCode == Keys.Z) {
            e.SuppressKeyPress = true;
            UndoLast();
        } else if (!e.Control && !e.Alt) {
            if (e.KeyCode == Keys.D1 || e.KeyCode == Keys.P) { _activeTool = DrawTool.Pen; UpdateToolbarHighlights(); }
            else if (e.KeyCode == Keys.D2 || e.KeyCode == Keys.H) { _activeTool = DrawTool.Highlighter; UpdateToolbarHighlights(); }
            else if (e.KeyCode == Keys.D3 || e.KeyCode == Keys.A) { _activeTool = DrawTool.Arrow; UpdateToolbarHighlights(); }
            else if (e.KeyCode == Keys.D4 || e.KeyCode == Keys.R) { _activeTool = DrawTool.Rectangle; UpdateToolbarHighlights(); }
            else if (e.KeyCode == Keys.D5 || e.KeyCode == Keys.E) { _activeTool = DrawTool.Ellipse; UpdateToolbarHighlights(); }
            else if (e.KeyCode == Keys.D6 || e.KeyCode == Keys.T) { _activeTool = DrawTool.Text; UpdateToolbarHighlights(); }
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.DrawImageUnscaled(_dimmedBmp, 0, 0);

        if (_selection.Width > 0 && _selection.Height > 0) {
            // Draw crisp original screenshot inside selection
            g.DrawImage(_screenBmp, _selection, _selection, GraphicsUnit.Pixel);

            // Clip annotations strictly to selection rectangle
            GraphicsState state = g.Save();
            g.SetClip(_selection);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            Point offset = _selection.Location;
            foreach (DrawAction act in _actions) {
                act.Render(g, offset);
            }
            if (_currentAction != null) {
                _currentAction.Render(g, offset);
            }
            g.Restore(state);

            // Selection border + dimensions badge
            using (Pen borderPen = new Pen(Color.FromArgb(255, 96, 165, 250), 2f)) {
                g.DrawRectangle(borderPen, _selection);
            }

            string info = string.Format("{0} \u00D7 {1} px   |   Rysuj na wycinku, a nast\u0119pnie wci\u015Bnij Ctrl+C (kompresja 768px w RAM i kopiowanie)", _selection.Width, _selection.Height);
            using (Font f = new Font("Segoe UI", 9f, FontStyle.Regular)) {
                SizeF sz = g.MeasureString(info, f);
                float bx = _selection.Left;
                float by = Math.Max(4, _selection.Top - sz.Height - 6);
                using (SolidBrush bg = new SolidBrush(Color.FromArgb(220, 15, 23, 42))) {
                    g.FillRectangle(bg, bx, by, sz.Width + 10, sz.Height + 4);
                }
                g.DrawString(info, f, Brushes.White, bx + 5, by + 2);
            }
        } else if (!_hasSelection) {
            // Crosshair guide before selecting
            using (Pen guidePen = new Pen(Color.FromArgb(110, 148, 163, 184), 1f)) {
                guidePen.DashStyle = DashStyle.Dash;
                g.DrawLine(guidePen, _mousePos.X, 0, _mousePos.X, this.Height);
                g.DrawLine(guidePen, 0, _mousePos.Y, this.Width, _mousePos.Y);
            }
            string hint = "Zaznacz obszar mysz\u0105 (PPM / Esc = anuluj)";
            using (Font f = new Font("Segoe UI Semibold", 10f, FontStyle.Bold)) {
                SizeF sz = g.MeasureString(hint, f);
                float hx = Math.Min(this.Width - sz.Width - 20, _mousePos.X + 16);
                float hy = Math.Min(this.Height - sz.Height - 20, _mousePos.Y + 16);
                using (SolidBrush bg = new SolidBrush(Color.FromArgb(210, 15, 23, 42))) {
                    g.FillRectangle(bg, hx, hy, sz.Width + 12, sz.Height + 6);
                }
                g.DrawString(hint, f, Brushes.White, hx + 6, hy + 3);
            }
        }
    }

    private void FinalizeAndCopy768() {
        CommitInlineText();
        if (!_hasSelection || _selection.Width < 4 || _selection.Height < 4) {
            this.Close();
            return;
        }

        // 1. Render annotated crop purely in RAM
        using (Bitmap annotated = new Bitmap(_selection.Width, _selection.Height, PixelFormat.Format24bppRgb)) {
            using (Graphics g = Graphics.FromImage(annotated)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

                g.DrawImage(_screenBmp, new Rectangle(0, 0, _selection.Width, _selection.Height), _selection, GraphicsUnit.Pixel);
                Point zero = new Point(0, 0);
                foreach (DrawAction act in _actions) {
                    act.Render(g, zero);
                }
            }

            // 2. Compress/resize to max 768px purely in RAM
            int maxDim = 768;
            int srcW = annotated.Width;
            int srcH = annotated.Height;

            if (srcW > maxDim || srcH > maxDim) {
                double ratio = Math.Min((double)maxDim / srcW, (double)maxDim / srcH);
                int outW = Math.Max(1, (int)Math.Round(srcW * ratio));
                int outH = Math.Max(1, (int)Math.Round(srcH * ratio));
                using (Bitmap resized = new Bitmap(outW, outH, PixelFormat.Format24bppRgb)) {
                    using (Graphics rg = Graphics.FromImage(resized)) {
                        rg.CompositingQuality = CompositingQuality.HighQuality;
                        rg.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        rg.SmoothingMode = SmoothingMode.HighQuality;
                        rg.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        rg.DrawImage(annotated, 0, 0, outW, outH);
                    }
                    Clipboard.SetImage(resized);
                }
            } else {
                Clipboard.SetImage(annotated);
            }
        }

        CopiedToClipboard = true;
        this.Close();
    }

    protected override void Dispose(bool disposing) {
        if (disposing) {
            if (_screenBmp != null) { _screenBmp.Dispose(); _screenBmp = null; }
            if (_dimmedBmp != null) { _dimmedBmp.Dispose(); _dimmedBmp = null; }
        }
        base.Dispose(disposing);
    }
}
"@

if ($CompileOnly) {
    Write-Output "CANVAS_COMPILED_OK"
    exit 0
}

[Win32DpiAndCapture]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

$canvasForm = New-Object WhisperCanvasForm
[System.Windows.Forms.Application]::Run($canvasForm)
if ($canvasForm.CopiedToClipboard) {
    Write-Output "CANVAS_COPIED_768"
}
$canvasForm.Dispose()
