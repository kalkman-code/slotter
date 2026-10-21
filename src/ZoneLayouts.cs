using System;
using System.Collections.Generic;
using System.Linq;

namespace Slotter
{
    public static class ZoneLayouts
    {
        public static double[][] Grid(int columns, int rows)
        {
            if (columns < 1 || columns > 20 || rows < 1 || rows > 20) return new double[0][];
            List<double[]> cells = new List<double[]>();
            for (int row = 0; row < rows; row++)
                for (int column = 0; column < columns; column++)
                {
                    double x = Math.Round(column * 100.0 / columns, 2), y = Math.Round(row * 100.0 / rows, 2);
                    double right = Math.Round((column + 1) * 100.0 / columns, 2), bottom = Math.Round((row + 1) * 100.0 / rows, 2);
                    cells.Add(new[] { x, y, Math.Round(right - x, 2), Math.Round(bottom - y, 2) });
                }
            return cells.ToArray();
        }

        public static double[] LargestFree(IEnumerable<Zone> zones)
        {
            List<double[]> occupied = new List<double[]>();
            foreach (Zone zone in zones)
            {
                if (!Finite(zone.X) || !Finite(zone.Y) || !Finite(zone.W) || !Finite(zone.H) || zone.W <= 0 || zone.H <= 0) continue;
                double left = Math.Max(0, zone.X), top = Math.Max(0, zone.Y);
                double right = Math.Min(100, zone.X + zone.W), bottom = Math.Min(100, zone.Y + zone.H);
                if (right > left && bottom > top) occupied.Add(new[] { left, top, right, bottom });
            }
            List<double> edges = occupied.SelectMany(r => new[] { r[0], r[2] }).Concat(new[] { 0.0, 100.0 }).Distinct().OrderBy(v => v).ToList();
            double[] best = null;
            double area = 0;
            for (int left = 0; left < edges.Count - 1; left++)
                for (int right = left + 1; right < edges.Count; right++)
                {
                    // Round inward so a saved two-decimal rectangle never overlaps an exact edge.
                    double x = Math.Ceiling(edges[left] * 100) / 100, endX = Math.Floor(edges[right] * 100) / 100;
                    if (endX - x < 1) continue;
                    List<double[]> intervals = occupied.Where(r => r[0] < endX && r[2] > x).OrderBy(r => r[1]).ToList();
                    double bottom = 0;
                    foreach (double[] r in intervals)
                    {
                        ConsiderFree(x, bottom, endX, r[1], ref best, ref area);
                        bottom = Math.Max(bottom, r[3]);
                    }
                    ConsiderFree(x, bottom, endX, 100, ref best, ref area);
                }
            return best;
        }

        static void ConsiderFree(double x, double y, double right, double bottom, ref double[] best, ref double area)
        {
            y = Math.Ceiling(y * 100) / 100;
            bottom = Math.Floor(bottom * 100) / 100;
            double w = Math.Round(right - x, 2), h = Math.Round(bottom - y, 2), candidate = w * h;
            if (w < 1 || h < 1) return;
            if (best == null || candidate > area + 0.0000001 || (Math.Abs(candidate - area) < 0.0000001 && (y < best[1] || (y == best[1] && x < best[0]))))
            { best = new[] { x, y, w, h }; area = candidate; }
        }

        static bool Finite(double value) { return !double.IsNaN(value) && !double.IsInfinity(value); }
    }
}
