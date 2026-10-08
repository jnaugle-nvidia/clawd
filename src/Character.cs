using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Clawd
{
    // Clawd: a blocky pixel crab. Everything is built on a unit grid (u) and snapped to
    // whole device pixels so the edges stay hard. Drawn in physical pixels, (0,0) at the
    // centre of the body.
    //
    // Grid, in units, with the body centre at the origin:
    //   body      x -5..5      y -4..3
    //   claws     x -6..-5 and 5..6,  y -2..0
    //   legs      four, 1.75 wide, hanging off the bottom edge
    //   eyes      1.7 squares centred at (+-2.6, -2.05)
    public static class Character
    {
        static readonly Brush Coral = Frozen(new SolidColorBrush(Color.FromRgb(0xD9, 0x77, 0x57)));
        static readonly Brush Sticker = Frozen(new SolidColorBrush(Color.FromRgb(0xFA, 0xF9, 0xF5)));
        static readonly Brush Ink = Frozen(new SolidColorBrush(Color.FromRgb(0x18, 0x14, 0x12)));
        static readonly Brush Shade = Frozen(new SolidColorBrush(Color.FromArgb(0x30, 0, 0, 0)));
        static readonly Brush Spark = Frozen(new SolidColorBrush(Color.FromRgb(0xFF, 0xC9, 0x6B)));
        static readonly Brush GhostCyan = Frozen(new SolidColorBrush(Color.FromArgb(0x55, 0x4F, 0xE0, 0xE8)));
        static readonly Brush GhostRed = Frozen(new SolidColorBrush(Color.FromArgb(0x50, 0xFF, 0x4D, 0x67)));
        static readonly Brush ScanLine = Frozen(new SolidColorBrush(Color.FromArgb(0x3A, 0xFF, 0xFF, 0xFF)));
        static readonly Brush HeartBrush = Frozen(new SolidColorBrush(Color.FromRgb(0xE2, 0x5C, 0x52)));
        static readonly Brush EyeShine = Frozen(new SolidColorBrush(Color.FromRgb(0xFA, 0xF9, 0xF5)));

        static readonly FontFamily Face = new FontFamily("Segoe UI");
        static Typeface bold, italic;

        static Brush Frozen(Brush b) { b.Freeze(); return b; }

        static Typeface Bold
        {
            get
            {
                if (bold == null) bold = new Typeface(Face, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
                return bold;
            }
        }

        static Typeface Italic
        {
            get
            {
                if (italic == null) italic = new Typeface(Face, FontStyles.Italic, FontWeights.Bold, FontStretches.Normal);
                return italic;
            }
        }

        // 5x5 square spiral for dizzy eyes.
        static readonly int[,] Spiral = new int[5, 5]
        {
            {1,1,1,1,1},
            {0,0,0,0,1},
            {1,1,1,0,1},
            {1,0,0,0,1},
            {1,1,1,1,1},
        };

        // 5x5 pixel heart.
        static readonly int[,] Heart = new int[5, 5]
        {
            {0,1,0,1,0},
            {1,1,1,1,1},
            {1,1,1,1,1},
            {0,1,1,1,0},
            {0,0,1,0,0},
        };

        public static void Draw(DrawingContext dc, Pet p)
        {
            double u = Math.Max(2, Math.Round(p.R / 5.0));

            double ease = 1 - Math.Pow(1 - p.Appear, 3);
            if (ease <= 0.02) return;

            // The shadow marks the ground plane: it does not bob, sway or spin.
            if (p.Grounded) DrawGroundShadow(dc, p, u);

            double sway = p.State == PetState.Dance ? Math.Round(p.DanceSwayPx) : 0;
            dc.PushTransform(new TranslateTransform(sway, Math.Round(p.Bob)));

            // Rotation happens in quarter turns only, which keeps the grid square:
            // continuous while tossed, a decaying twirl during a dance accent.
            double q = Math.Round(p.Spin / 90.0) * 90.0 % 360.0;
            bool rot = q > 0.5 || q < -0.5;
            if (rot) dc.PushTransform(new RotateTransform(q));

            // Scaling is allowed in two places only. The spawn pop lasts about half a second...
            bool popping = p.Appear < 0.999;
            if (popping)
            {
                double pop = ease * (1 + 0.12 * Math.Sin(p.Appear * Math.PI));
                dc.PushTransform(new ScaleTransform(pop, pop));
            }

            // ...and the "Claude needs you" throb, which is meant to be impossible to miss.
            bool throbbing = p.NeedsYouScale != 1;
            if (throbbing) dc.PushTransform(new ScaleTransform(p.NeedsYouScale, p.NeedsYouScale));

            List<Rect> parts = BuildParts(p, u);

            if (p.GlitchAmt > 0.01) DrawGlitched(dc, p, u, parts);
            else DrawCrab(dc, p, u, parts);

            if (throbbing) dc.Pop();
            if (popping) dc.Pop();
            if (rot) dc.Pop();
            dc.Pop();

            DrawParticles(dc, p, u);
            if (p.SayT > 0 && p.Say.Length > 0) DrawBubble(dc, p, u);
        }

        static void DrawCrab(DrawingContext dc, Pet p, double u, List<Rect> parts)
        {
            for (int i = 0; i < parts.Count; i++)
                dc.DrawRectangle(Coral, null, parts[i]);
            DrawEyes(dc, p, u);
        }

        // ---- hologram glitch ----
        // RGB ghost fringes behind the body, the sprite sliced into bands that jump
        // sideways, the odd band dropping out entirely, and a scanline shimmer.

        static void DrawGlitched(DrawingContext dc, Pet p, double u, List<Rect> parts)
        {
            int seed = p.GlitchSeed;
            dc.PushOpacity(0.72 + 0.28 * H(seed, 99));            // signal flicker

            double off = Math.Max(1, Math.Round(u * (0.5 + 1.7 * H(seed, 50))));
            double jy = Math.Round((H(seed, 51) - 0.5) * u * 0.8);

            dc.PushTransform(new TranslateTransform(-off, jy));
            for (int i = 0; i < parts.Count; i++)
                dc.DrawRectangle(GhostCyan, null, parts[i]);
            dc.Pop();

            dc.PushTransform(new TranslateTransform(Math.Max(1, Math.Round(off * 0.7)), -jy));
            for (int i = 0; i < parts.Count; i++)
                dc.DrawRectangle(GhostRed, null, parts[i]);
            dc.Pop();

            Rect box = new Rect(-7 * u, -5 * u, 14 * u, 11 * u);
            int bands = 5;
            double bh = box.Height / bands;
            for (int i = 0; i < bands; i++)
            {
                if (H(seed, i * 7 + 3) < 0.10) continue;          // dropout: signal loss
                double hh = H(seed, i * 3 + 1);
                double dx = hh < 0.5 ? Math.Round((hh - 0.25) * 4 * 1.3 * u) : 0;
                dc.PushClip(new RectangleGeometry(new Rect(box.X, box.Y + i * bh, box.Width, bh)));
                dc.PushTransform(new TranslateTransform(dx, 0));
                DrawCrab(dc, p, u, parts);
                dc.Pop();
                dc.Pop();
            }

            // scanlines, clipped to the body so they never reveal the window rectangle
            for (int k = 0; k < 2; k++)
            {
                double sy = box.Y + H(seed, 60 + k) * box.Height;
                Rect scan = new Rect(box.X, sy, box.Width, Math.Max(1, Math.Round(u * 0.22)));
                for (int j = 0; j < parts.Count; j++)
                {
                    Rect ri = Rect.Intersect(parts[j], scan);
                    if (!ri.IsEmpty && ri.Width > 0 && ri.Height > 0)
                        dc.DrawRectangle(ScanLine, null, ri);
                }
            }

            dc.Pop();
        }

        // Deterministic per-seed noise so a glitch frame holds still until the seed rerolls.
        static double H(int seed, int i)
        {
            unchecked
            {
                uint x = (uint)(seed * 73856093) ^ (uint)(i * 19349663);
                x ^= x << 13; x ^= x >> 17; x ^= x << 5;
                return (x % 10000u) / 10000.0;
            }
        }

        // ---- silhouette ----

        static List<Rect> BuildParts(Pet p, double u)
        {
            List<Rect> parts = new List<Rect>();

            // Moving fast squashes the body a unit wider and shorter.
            double sq = p.Squash > 0.07 ? 1 : 0;
            double bodyL = -5 * u - sq * 0.4 * u;
            double bodyR = 5 * u + sq * 0.4 * u;
            double bodyT = -4 * u + sq * 0.5 * u;
            double bodyB = 3 * u;
            parts.Add(LTRB(bodyL, bodyT, bodyR, bodyB));

            // Claws lift when happy or when the cursor is on the pet: it waves.
            // Dancing, they alternate on the beat - or both go up for "raise the roof".
            double liftL, liftR;
            if (p.State == PetState.Dance)
            {
                double up = -(0.5 + 1.1 * p.DancePulse) * u;
                if (p.DanceMove == 1) { liftL = up; liftR = up; }
                else if (p.DanceParity) { liftL = up; liftR = 0; }
                else { liftL = 0; liftR = up; }
            }
            else
            {
                double lift = 0;
                if (p.Mood == Mood.Happy) lift = -1.0 * u;
                else if (p.HoverPop > 0.3) lift = -0.6 * u * p.HoverPop;
                else if (p.Mood == Mood.Surprised) lift = -0.5 * u;
                if (p.Grounded && Math.Abs(p.VX) > 25) lift += Math.Sin(p.Clock * 9) * 0.25 * u;
                liftL = liftR = lift;
            }

            parts.Add(LTRB(bodyL - u, -2 * u + liftL, bodyL, 0 * u + liftL));
            parts.Add(LTRB(bodyR, -2 * u + liftR, bodyR + u, 0 * u + liftR));

            // Four legs. Tucked up a little while airborne; alternate kicks on the beat.
            double legLen = p.Grounded ? 2.3 * u : 1.9 * u;
            bool dancing = p.State == PetState.Dance;
            bool walking = p.Grounded && Math.Abs(p.VX) > 25 && !dancing;
            double[] lx = new double[] { -5.0, -2.25, 0.5, 3.25 };
            for (int i = 0; i < 4; i++)
            {
                double step = 0;
                if (walking) step = Math.Sin(p.Clock * 9 + i * 1.7) > 0 ? -0.45 * u : 0;
                else if (dancing && ((i % 2 == 0) == p.DanceParity)) step = -0.6 * u * p.DancePulse;
                parts.Add(LTRB(lx[i] * u, bodyB, (lx[i] + 1.75) * u, bodyB + legLen + step));
            }

            // The middle notch is shallower than the outer two.
            parts.Add(LTRB(-0.5 * u, bodyB, 0.5 * u, bodyB + Math.Min(1.0 * u, legLen)));

            return parts;
        }

        static Rect LTRB(double l, double t, double r, double b)
        {
            double x = Math.Round(l), y = Math.Round(t);
            return new Rect(x, y, Math.Max(1, Math.Round(r) - x), Math.Max(1, Math.Round(b) - y));
        }

        static void DrawGroundShadow(DrawingContext dc, Pet p, double u)
        {
            double y = 3 * u + 2.3 * u + 0.5 * u;
            dc.DrawRectangle(Shade, null, LTRB(-4.2 * u, y, 4.2 * u, y + 0.55 * u));
        }

        // ---- eyes ----

        static void DrawEyes(DrawingContext dc, Pet p, double u)
        {
            // Dancing reads as happy unless something stronger is showing.
            Mood mood = p.Mood;
            if (p.State == PetState.Dance && (mood == Mood.Neutral || mood == Mood.Curious))
                mood = Mood.Happy;

            double dx = Math.Round(p.LookX * 0.55 * u);
            double dy = Math.Round(p.LookY * 0.45 * u);
            double ey = -2.05 * u + dy;

            for (int s = -1; s <= 1; s += 2)
            {
                double ex = s * 2.6 * u + dx;
                bool shut = mood == Mood.Sleepy || p.Blink > 0.55;

                if (shut)
                {
                    dc.DrawRectangle(Ink, null, LTRB(ex - 0.85 * u, ey - 0.22 * u, ex + 0.85 * u, ey + 0.22 * u));
                }
                else if (mood == Mood.Happy)
                {
                    // stepped chevron: ^ ^
                    double k = 0.56 * u;
                    dc.DrawRectangle(Ink, null, LTRB(ex - 1.5 * k, ey + 0.1 * u, ex - 0.5 * k, ey + 0.1 * u + k));
                    dc.DrawRectangle(Ink, null, LTRB(ex - 0.5 * k, ey - 0.5 * u, ex + 0.5 * k, ey - 0.5 * u + k));
                    dc.DrawRectangle(Ink, null, LTRB(ex + 0.5 * k, ey + 0.1 * u, ex + 1.5 * k, ey + 0.1 * u + k));
                }
                else if (mood == Mood.Dizzy)
                {
                    double c = 0.42 * u;
                    for (int gy = 0; gy < 5; gy++)
                        for (int gx = 0; gx < 5; gx++)
                            if (Spiral[gy, gx] != 0)
                                dc.DrawRectangle(Ink, null,
                                    LTRB(ex + (gx - 2.5) * c, ey + (gy - 2.5) * c,
                                         ex + (gx - 1.5) * c, ey + (gy - 1.5) * c));
                }
                else
                {
                    double half = (mood == Mood.Surprised ? 1.0 : 0.85) * u;
                    double hh = half * (1 - p.Blink * 0.85);
                    dc.DrawRectangle(Ink, null, LTRB(ex - half, ey - hh, ex + half, ey + hh));
                    if (mood == Mood.Surprised || mood == Mood.Curious)
                        dc.DrawRectangle(EyeShine, null,
                            LTRB(ex - half + 0.18 * u, ey - hh + 0.18 * u,
                                 ex - half + 0.62 * u, ey - hh + 0.62 * u));
                }
            }
        }

        // ---- particles ----

        static void DrawParticles(DrawingContext dc, Pet p, double u)
        {
            for (int i = 0; i < p.Parts.Count; i++)
            {
                Particle q = p.Parts[i];
                double a = Math.Max(0, Math.Min(1, q.Life / q.MaxLife));
                double fade = a > 0.7 ? (1 - a) / 0.3 : a / 0.7;
                fade = Math.Max(0, Math.Min(1, fade));
                if (fade <= 0.02) continue;

                dc.PushOpacity(fade);
                switch (q.Kind)
                {
                    case 0: DrawSparkle(dc, q); break;
                    case 1: DrawPixelGrid(dc, Heart, q.X, q.Y, q.Size * 0.42, HeartBrush); break;
                    case 2: DrawGlyph(dc, q, "z", Italic, Color.FromRgb(0xD9, 0x77, 0x57)); break;
                    default: DrawGlyph(dc, q, "!", Bold, Color.FromRgb(0xD9, 0x77, 0x57)); break;
                }
                dc.Pop();
            }
        }

        // A pixel sparkle: a plus, with the arms trimmed as it fades.
        static void DrawSparkle(DrawingContext dc, Particle q)
        {
            double c = Math.Max(1, Math.Round(q.Size * 0.42));
            double x = Math.Round(q.X), y = Math.Round(q.Y);
            dc.DrawRectangle(Spark, null, new Rect(x - c * 0.5, y - c * 1.5, c, c * 3));
            dc.DrawRectangle(Spark, null, new Rect(x - c * 1.5, y - c * 0.5, c * 3, c));
        }

        static void DrawPixelGrid(DrawingContext dc, int[,] grid, double cx, double cy, double c, Brush b)
        {
            c = Math.Max(1, Math.Round(c));
            int n = grid.GetLength(0);
            double ox = Math.Round(cx - n * c / 2), oy = Math.Round(cy - n * c / 2);
            for (int gy = 0; gy < n; gy++)
                for (int gx = 0; gx < n; gx++)
                    if (grid[gy, gx] != 0)
                        dc.DrawRectangle(b, null, new Rect(ox + gx * c, oy + gy * c, c, c));
        }

        static void DrawGlyph(DrawingContext dc, Particle q, string text, Typeface tf, Color col)
        {
            SolidColorBrush b = new SolidColorBrush(col);
            b.Freeze();
            FormattedText ft = new FormattedText(text, CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight, tf, Math.Max(7, q.Size), b);
            dc.DrawText(ft, new Point(Math.Round(q.X - ft.Width / 2), Math.Round(q.Y - ft.Height / 2)));
        }

        // ---- speech bubble ----

        static void DrawBubble(DrawingContext dc, Pet p, double u)
        {
            double fade = p.SayT > 0.45 ? 1.0 : p.SayT / 0.45;
            fade = Math.Min(1, fade);

            FormattedText ft = new FormattedText(p.Say, CultureInfo.CurrentCulture,
                FlowDirection.LeftToRight, Bold, Math.Max(10, u * 1.5), Ink);
            ft.MaxTextWidth = u * 20;

            double padX = u * 0.9, padY = u * 0.55;
            double w = Math.Round(ft.Width + padX * 2), h = Math.Round(ft.Height + padY * 2);
            double left = Math.Round(-w / 2), top = Math.Round(-5.6 * u - h);

            dc.PushOpacity(fade);

            double b = Math.Max(1, Math.Round(u * 0.22));
            dc.DrawRectangle(Ink, null, new Rect(left - b, top - b, w + b * 2, h + b * 2));
            dc.DrawRectangle(Sticker, null, new Rect(left, top, w, h));

            // stepped tail
            double t0 = top + h;
            dc.DrawRectangle(Ink, null, new Rect(-1.6 * u - b, t0, 1.6 * u + b * 2, u * 0.7 + b));
            dc.DrawRectangle(Ink, null, new Rect(-1.6 * u - b, t0 + u * 0.7, 0.9 * u + b * 2, u * 0.7 + b));
            dc.DrawRectangle(Sticker, null, new Rect(-1.6 * u, t0 - 1, 1.6 * u, u * 0.7 + 1));
            dc.DrawRectangle(Sticker, null, new Rect(-1.6 * u, t0 + u * 0.7 - 1, 0.9 * u, u * 0.7 + 1));

            dc.DrawText(ft, new Point(Math.Round(left + padX), Math.Round(top + padY)));
            dc.Pop();
        }
    }
}
